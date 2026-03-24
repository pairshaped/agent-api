# Deploy Improvements: Ansistrano-Inspired Patterns

## Summary

Improve the custom Ansible deploy by adopting three patterns from Ansistrano: persistent git repo with `git archive` export, remove-then-symlink for shared paths, and block/rescue for failed release cleanup. Keep our atomic symlink swap. Goal is reliability and alignment with Ansistrano conventions for easier future migration.

## 1. Persistent Repo + Git Archive

### Current

Each deploy does a fresh `git clone` into the release directory. Slow (full clone every time), and the release dir ends up with `.git/` metadata.

### New

A persistent clone lives at `base_dir/repo/`. On deploy:

1. `ansible.builtin.git` updates `repo/` (fetch delta only — fast)
2. `git -C repo/ archive HEAD | tar -x -C releases/<timestamp>/` exports a clean copy (no `.git/`)

This mirrors Ansistrano's git strategy (persistent `repo/` + export into release dir), except we use `git archive` instead of rsync since it's a single server.

### Setup (setup.yml App Setup section)

All app-level tasks use `become: false` (Play 2 has `become: true` at play level for system tasks).

1. Create `repo/` directory (owned by deploy user)
2. Create `releases/` directory (owned by deploy user)
3. Create `shared/` and `shared/db/` directories (owned by deploy user)
4. Generate `shared/.env` (with `creates:` guard)
5. `ansible.builtin.git` clone into `repo/` (initial full clone, `become: false`)
6. Generate initial release timestamp
7. Create release directory `releases/<timestamp>/`
8. `git -C repo/ archive HEAD | tar -x -C releases/<timestamp>/`
9. Remove `.env` and `db/gleam_mcp_todo.db` from release dir (idempotent)
10. Symlink `shared/.env` and `shared/db/gleam_mcp_todo.db` into release dir
11. `gleam build` in release dir
12. `bin/migrate` in release dir
13. Create `current` symlink to release dir
14. Install systemd service, enable and start

### Directory structure

```
/home/deploy/gleam-mcp-todo/
  repo/                                    # persistent git clone
  releases/
    20260324_143012/
    20260324_151530/
  current -> releases/20260324_151530/
  shared/
    .env
    db/gleam_mcp_todo.db
```

## 2. Remove-Then-Symlink for Shared Paths

### Current

Symlink tasks use `force: true` but fail if the target is a non-empty directory (the `db/` bug we hit). We worked around it by symlinking only the `.db` file, but this is fragile.

### New

Before symlinking, explicitly remove the cloned target. The remove must be idempotent (`ansible.builtin.file` with `state: absent`) since the files may not exist in the archive (`.env` is never committed, `db/gleam_mcp_todo.db` is gitignored):

1. Remove `releases/<timestamp>/.env` (if exists)
2. Remove `releases/<timestamp>/db/gleam_mcp_todo.db` (if exists)
3. Symlink `shared/.env` → `releases/<timestamp>/.env`
4. Symlink `shared/db/gleam_mcp_todo.db` → `releases/<timestamp>/db/gleam_mcp_todo.db`

With `git archive`, there's no `.git/` to worry about, but the repo still contains `db/migrations/` and possibly a `.env.example`. The remove-then-symlink pattern makes this safe regardless of repo contents.

Note: the `db/` directory must exist in the release for the `.db` symlink to work. Currently `db/migrations/` is tracked in the repo so `git archive` includes `db/`. If that ever changes, the deploy would need to `mkdir -p db/` before symlinking.

## 3. Block/Rescue for Failed Release Cleanup

### Current

If `gleam build` or `bin/migrate` fails, the broken release directory is left on disk. It counts toward the 5-release limit and wastes space.

### New

Wrap build + migrate in an Ansible `block/rescue`:

```yaml
- block:
    - name: Build
      ...
    - name: Run migrations
      ...
  rescue:
    - name: Show deploy error
      ansible.builtin.debug:
        msg: "{{ ansible_failed_result }}"
    - name: Remove failed release
      ansible.builtin.file:
        path: "{{ release_dir }}"
        state: absent
    - name: Fail with message
      ansible.builtin.fail:
        msg: "Deploy failed. Release {{ release_name }} removed. Current release unchanged."
```

On failure: broken release is cleaned up, `current` symlink untouched, clear error message. On success: continues to symlink swap + restart.

## Deploy Flow (Complete)

1. Generate release timestamp
2. Create release directory
3. Pre-flight: verify `shared/.env` exists
4. Update `repo/` via `ansible.builtin.git` (fetch + checkout `deploy_ref`)
5. `git archive HEAD | tar -x` from `repo/` into release dir
6. Remove cloned `.env` and `db/gleam_mcp_todo.db` from release dir
7. Symlink `shared/.env` and `shared/db/gleam_mcp_todo.db` into release dir
8. **Block:**
   - `gleam build`
   - `bin/migrate`
9. Atomic symlink swap (`ln -s && mv -T`)
10. Restart systemd
11. Cleanup old releases (keep 5, protect `current`)
12. **Rescue (on step 8 failure):** remove release dir, fail

## Configuration (vars.yml)

Add one new variable:

```yaml
repo_dir: /home/deploy/gleam-mcp-todo/repo
```

All other vars unchanged.

## What Changes

| File | Change |
|------|--------|
| `ansible/deploy.yml` | Persistent repo update, git archive, remove-then-symlink, block/rescue |
| `ansible/setup.yml` | Create `repo/`, initial clone there, git archive into first release |
| `ansible/vars.yml` | Add `repo_dir` |
| `ansible/vars.yml.example` | Add `repo_dir` |

## What Doesn't Change

- `ansible/rollback.yml` — unchanged
- `ansible/templates/` — unchanged
- `bin/deploy`, `bin/rollback` — unchanged
- `bin/deploy-docker` — unchanged

## Ansistrano Alignment

These changes align our deploy with Ansistrano's conventions:

| Ansistrano Pattern | Our Implementation |
|---|---|
| Persistent `repo/` directory | Same — `base_dir/repo/` |
| Export from repo into release (rsync) | `git archive \| tar -x` (simpler, single server) |
| Remove shared targets before symlinking | Same — explicit remove before symlink |
| Rescue block on deploy failure | Same — remove failed release, fail cleanly |
| `file: state=link` symlink swap | Better — `ln -s && mv -T` (truly atomic) |

If we later migrate to Ansistrano roles, the directory structure and shared path conventions are already compatible.
