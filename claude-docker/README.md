# Docker Setup — linak-control

Config: secure
Installed: 2026-04-01
Image: claude-code-secure:1.0

## Start

```bash
./begin-code.sh
```

## Options

```bash
./begin-code.sh --bash    # start bash shell instead of Claude
./begin-code.sh --yolo    # skip permission prompts
./begin-code.sh --login   # force re-authentication
```

## Files

```
claude-docker/claude-docker-linak-control.json   — Docker configuration
claude-docker/Dockerfile                              — Multi-stage Docker image template
claude-docker-home/                                   — Claude Code home (mounted as /home/coder)
begin-code.sh                                         — Session start script
```
