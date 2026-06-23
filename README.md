# oh-my-skills

A curated, auto-synced collection of AI agent skills from multiple upstream GitHub repositories.

## How It Works

- **`upstreams.txt`** — declare upstream repos (one per line)
- **`scripts/sync-skills.sh`** — sparse-checks out only the `skills/` directory from each upstream and rsyncs into your local `skills/` tree
- **GitHub Actions** — runs the sync every 6 hours automatically

## Add an Upstream

Edit `upstreams.txt`, then:

```bash
./scripts/update.sh          # sync + commit + push
./scripts/update.sh --ci     # also trigger GitHub Action
```

## upstreams.txt Format

```
URL:BRANCH:LOCAL_PREFIX
```

```
# Comments and blank lines are ignored
https://github.com/JuliusBrussee/caveman.git:main:caveman
JuliusBrussee/caveman:main:caveman              # shorthand also works
```

Each upstream's skills land under `skills/<LOCAL_PREFIX>/`.

## Manual Sync

```bash
./scripts/sync-skills.sh
git add -A && git commit -m "chore(skills): manual sync" && git push
```
