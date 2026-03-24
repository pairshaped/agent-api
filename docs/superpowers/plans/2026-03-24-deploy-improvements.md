# Deploy Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the Ansible deploy with a persistent git repo, remove-then-symlink for shared paths, and block/rescue for failed release cleanup.

**Architecture:** A persistent `repo/` clone is updated on each deploy, then `git archive` exports a clean copy into the release dir. Shared paths are removed before symlinking (idempotent). Build + migrate are wrapped in block/rescue to auto-clean failed releases.

**Tech Stack:** Ansible, Bash, Git

**Spec:** `docs/superpowers/specs/2026-03-24-deploy-improvements-design.md`

---

### Task 1: Add repo_dir to vars

**Files:**
- Modify: `ansible/vars.yml`
- Modify: `ansible/vars.yml.example`

- [ ] **Step 1: Add repo_dir to vars.yml**

Add after the `current_link` line in `ansible/vars.yml`:

```yaml
repo_dir: /home/deploy/gleam-mcp-todo/repo
```

- [ ] **Step 2: Add repo_dir to vars.yml.example**

Add after the `current_link` line in `ansible/vars.yml.example`:

```yaml
repo_dir: /home/deploy/gleam-mcp-todo/repo
```

- [ ] **Step 3: Commit**

```bash
git add ansible/vars.yml.example
git commit -m "Add repo_dir variable for persistent git clone"
```

Note: `ansible/vars.yml` is gitignored, so only the example is committed.

---

### Task 2: Rewrite deploy.yml

**Files:**
- Modify: `ansible/deploy.yml`

- [ ] **Step 1: Replace deploy.yml**

Replace the entire contents of `ansible/deploy.yml` with:

```yaml
---
# Deploy latest code using release directories.
# Usage: ansible-playbook ansible/deploy.yml -i ansible/inventory.ini
# Deploy a specific ref: ansible-playbook ansible/deploy.yml -i ansible/inventory.ini -e deploy_ref=v1.2.0

- name: Deploy Todo List MCP Server
  hosts: servers
  vars_files:
    - vars.yml

  tasks:
    - name: Generate release timestamp
      ansible.builtin.set_fact:
        release_name: "{{ lookup('pipe', 'date +%Y%m%d_%H%M%S') }}"

    - name: Set release directory
      ansible.builtin.set_fact:
        release_dir: "{{ releases_dir }}/{{ release_name }}"

    - name: Show deploy target
      ansible.builtin.debug:
        msg: "Deploying {{ deploy_ref }} to {{ release_dir }}"

    - name: Verify shared .env exists
      ansible.builtin.stat:
        path: "{{ shared_dir }}/.env"
      register: shared_env

    - name: Fail if shared .env missing
      ansible.builtin.fail:
        msg: "{{ shared_dir }}/.env not found. Run setup.yml first."
      when: not shared_env.stat.exists

    - name: Update persistent repo
      ansible.builtin.git:
        repo: "{{ repo_url }}"
        dest: "{{ repo_dir }}"
        version: "{{ deploy_ref }}"
        accept_hostkey: true

    - name: Create release directory
      ansible.builtin.file:
        path: "{{ release_dir }}"
        state: directory
        mode: "0755"

    - name: Export repo into release directory
      ansible.builtin.shell: |
        git -C "{{ repo_dir }}" archive HEAD | tar -x -C "{{ release_dir }}"

    - name: Remove cloned .env from release
      ansible.builtin.file:
        path: "{{ release_dir }}/.env"
        state: absent

    - name: Remove cloned database from release
      ansible.builtin.file:
        path: "{{ release_dir }}/db/gleam_mcp_todo.db"
        state: absent

    - name: Symlink shared .env into release
      ansible.builtin.file:
        src: "{{ shared_dir }}/.env"
        dest: "{{ release_dir }}/.env"
        state: link

    - name: Symlink shared database into release
      ansible.builtin.file:
        src: "{{ shared_dir }}/db/gleam_mcp_todo.db"
        dest: "{{ release_dir }}/db/gleam_mcp_todo.db"
        state: link

    - block:
        - name: Build
          ansible.builtin.command:
            cmd: gleam build
            chdir: "{{ release_dir }}"
          register: build_result
          changed_when: "'Compiled' in build_result.stderr"

        - name: Run migrations
          ansible.builtin.command:
            cmd: bin/migrate
            chdir: "{{ release_dir }}"
          register: migrate_result
          changed_when: "'Running migration' in migrate_result.stdout"

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

    - name: Atomic symlink swap
      ansible.builtin.shell: |
        ln -s "{{ release_dir }}" "{{ current_link }}_tmp" && mv -T "{{ current_link }}_tmp" "{{ current_link }}"
      args:
        chdir: "{{ base_dir }}"

    - name: Restart gleam-mcp-todo
      ansible.builtin.systemd:
        name: gleam-mcp-todo
        state: restarted
      become: true

    - name: Find old releases to clean up
      ansible.builtin.shell: |
        ls -1d {{ releases_dir }}/*/ | sort | head -n -{{ keep_releases }} | grep -v "$(readlink -f {{ current_link }})" || true
      register: old_releases
      changed_when: false

    - name: Remove old releases
      ansible.builtin.file:
        path: "{{ item }}"
        state: absent
      loop: "{{ old_releases.stdout_lines }}"
      when: old_releases.stdout_lines | length > 0
```

- [ ] **Step 2: Verify syntax**

Run: `ansible-playbook ansible/deploy.yml --syntax-check`
Expected: `playbook: ansible/deploy.yml` (no errors)

- [ ] **Step 3: Commit**

```bash
git add ansible/deploy.yml
git commit -m "Rewrite deploy.yml with persistent repo, remove-then-symlink, block/rescue"
```

---

### Task 3: Update setup.yml App Setup section

**Files:**
- Modify: `ansible/setup.yml` (lines 204 onward — the `# --- App setup ---` section through end of file)

- [ ] **Step 1: Replace the App setup section**

Replace everything from line 204 (`# --- App setup ---`) through the end of `ansible/setup.yml` with:

```yaml
    # --- App setup ---

    - name: Create persistent repo directory
      ansible.builtin.file:
        path: "{{ repo_dir }}"
        state: directory
        owner: "{{ deploy_user }}"
        group: "{{ deploy_user }}"
        mode: "0755"

    - name: Create releases directory
      ansible.builtin.file:
        path: "{{ releases_dir }}"
        state: directory
        owner: "{{ deploy_user }}"
        group: "{{ deploy_user }}"
        mode: "0755"

    - name: Create shared directory
      ansible.builtin.file:
        path: "{{ shared_dir }}"
        state: directory
        owner: "{{ deploy_user }}"
        group: "{{ deploy_user }}"
        mode: "0755"

    - name: Create shared db directory
      ansible.builtin.file:
        path: "{{ shared_dir }}/db"
        state: directory
        owner: "{{ deploy_user }}"
        group: "{{ deploy_user }}"
        mode: "0755"

    - name: Generate shared .env
      ansible.builtin.shell: |
        SECRET=$(openssl rand -hex 32)
        echo "SESSION_SECRET=$SECRET" > {{ shared_dir }}/.env
        echo "DOMAIN={{ domain }}" >> {{ shared_dir }}/.env
        echo "DB_PATH={{ shared_dir }}/db/gleam_mcp_todo.db" >> {{ shared_dir }}/.env
        echo "PORT=8080" >> {{ shared_dir }}/.env
      args:
        creates: "{{ shared_dir }}/.env"
      become: false

    - name: Clone repo
      ansible.builtin.git:
        repo: "{{ repo_url }}"
        dest: "{{ repo_dir }}"
        version: "{{ deploy_ref }}"
        accept_hostkey: true
      become: false

    - name: Generate initial release timestamp
      ansible.builtin.set_fact:
        initial_release: "{{ lookup('pipe', 'date +%Y%m%d_%H%M%S') }}"

    - name: Create initial release directory
      ansible.builtin.file:
        path: "{{ releases_dir }}/{{ initial_release }}"
        state: directory
        owner: "{{ deploy_user }}"
        group: "{{ deploy_user }}"
        mode: "0755"

    - name: Export repo into initial release
      ansible.builtin.shell: |
        git -C "{{ repo_dir }}" archive HEAD | tar -x -C "{{ releases_dir }}/{{ initial_release }}"
      become: false

    - name: Remove cloned .env from initial release
      ansible.builtin.file:
        path: "{{ releases_dir }}/{{ initial_release }}/.env"
        state: absent
      become: false

    - name: Remove cloned database from initial release
      ansible.builtin.file:
        path: "{{ releases_dir }}/{{ initial_release }}/db/gleam_mcp_todo.db"
        state: absent
      become: false

    - name: Symlink shared .env into initial release
      ansible.builtin.file:
        src: "{{ shared_dir }}/.env"
        dest: "{{ releases_dir }}/{{ initial_release }}/.env"
        state: link
      become: false

    - name: Symlink shared database into initial release
      ansible.builtin.file:
        src: "{{ shared_dir }}/db/gleam_mcp_todo.db"
        dest: "{{ releases_dir }}/{{ initial_release }}/db/gleam_mcp_todo.db"
        state: link
      become: false

    - name: Build initial release
      ansible.builtin.command:
        cmd: gleam build
        chdir: "{{ releases_dir }}/{{ initial_release }}"
      become: false

    - name: Run migrations
      ansible.builtin.command:
        cmd: bin/migrate
        chdir: "{{ releases_dir }}/{{ initial_release }}"
      become: false

    - name: Create current symlink
      ansible.builtin.file:
        src: "{{ releases_dir }}/{{ initial_release }}"
        dest: "{{ current_link }}"
        state: link
        force: true
      become: false

    - name: Install systemd service
      ansible.builtin.template:
        src: templates/gleam-mcp-todo.service.j2
        dest: /etc/systemd/system/gleam-mcp-todo.service
        mode: "0644"
      notify:
        - Reload systemd
        - Restart gleam-mcp-todo

    - name: Enable and start gleam-mcp-todo
      ansible.builtin.systemd:
        name: gleam-mcp-todo
        enabled: true
        state: started

  handlers:
    - name: Reload caddy
      ansible.builtin.systemd:
        name: caddy
        state: restarted

    - name: Reload systemd
      ansible.builtin.systemd:
        daemon_reload: true

    - name: Restart gleam-mcp-todo
      ansible.builtin.systemd:
        name: gleam-mcp-todo
        state: restarted
```

- [ ] **Step 2: Verify syntax**

Run: `ansible-playbook ansible/setup.yml --syntax-check`
Expected: `playbook: ansible/setup.yml` (no errors)

- [ ] **Step 3: Commit**

```bash
git add ansible/setup.yml
git commit -m "Update setup.yml with persistent repo and remove-then-symlink"
```

---

### Task 4: Test on server

The server is already provisioned. We can test by deploying (which will create `repo/` on first run if it doesn't exist — though it won't, so the `ansible.builtin.git` task will do a full clone on the first deploy, then incremental fetches after).

Actually, `deploy.yml` assumes `repo/` already exists (created by `setup.yml`). Since our server was set up with the previous version, we need to create `repo/` manually first.

- [ ] **Step 1: Create repo directory on server**

Run: `ssh deploy@137.184.168.49 'git clone git@github.com:pairshaped/gleam-mcp-todo.git /home/deploy/gleam-mcp-todo/repo'`
Expected: Repo cloned into `/home/deploy/gleam-mcp-todo/repo/`

- [ ] **Step 2: Push changes**

Run: `git push`

- [ ] **Step 3: Deploy**

Run: `bin/deploy`
Expected: Deploy uses persistent repo + git archive. New release created, symlink swapped, app restarted.

- [ ] **Step 4: Verify release has no .git directory**

Run: `ssh deploy@137.184.168.49 'ls -la /home/deploy/gleam-mcp-todo/releases/$(ls -t /home/deploy/gleam-mcp-todo/releases/ | head -1)/.git 2>&1'`
Expected: "No such file or directory" (git archive produces clean exports)

- [ ] **Step 5: Verify shared symlinks**

Run: `ssh deploy@137.184.168.49 'ls -la /home/deploy/gleam-mcp-todo/current/.env /home/deploy/gleam-mcp-todo/current/db/gleam_mcp_todo.db'`
Expected: Both are symlinks pointing to shared/

- [ ] **Step 6: Deploy again to verify incremental fetch**

Run: `bin/deploy`
Expected: Faster than first deploy (delta fetch only). Third release created.

- [ ] **Step 7: Test rollback still works**

Run: `bin/rollback`
Expected: Rolled back to previous release. App still works.

- [ ] **Step 8: Test block/rescue failure cleanup**

Run: `bin/deploy nonexistent-branch-that-does-not-exist`
Expected: Deploy fails at the git update step. Check that no new broken release was left behind:
Run: `ssh deploy@137.184.168.49 'ls /home/deploy/gleam-mcp-todo/releases/ | wc -l'`
Expected: Same count as before the failed deploy.

- [ ] **Step 9: Verify app is still accessible after failed deploy**

Run: `curl -s -o /dev/null -w "%{http_code}" https://todomcp.curling.dev`
Expected: `200`
