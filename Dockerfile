# syntax=docker/dockerfile:1
#
# Image holds only the code. Secrets come from .env (env_file in compose);
# game data comes from the ./data bind mount at /app/data.
#
# python:3.12-slim is multi-arch, so this builds on a Raspberry Pi
# (arm64/armv7) and on a PC alike.

FROM python:3.12-slim

# CAIRN_DATA_DIR must match the volume target in docker-compose.yml.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    CAIRN_DATA_DIR=/app/data

WORKDIR /app

# Dependencies first, so editing app.py doesn't invalidate the pip layer.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# app.py is the whole app (templates are inline). Never COPY data/ or .env.
COPY app.py ./

# Non-root without creating a user in the image: a numeric USER needs no
# account. Compose overrides it with PUID:PGID so the app writes ./data as
# the host user who owns it. 1000:1000 is the fallback without compose.
USER 1000:1000

EXPOSE 5000

# urllib, because curl isn't in the slim image. / answers 200 without a
# login (it shows the character creation page to a new visitor).
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request as u, sys; sys.exit(0 if u.urlopen('http://127.0.0.1:5000/', timeout=4).status == 200 else 1)"]

# One process, several threads: game state is held in memory, so it must not
# be split across worker processes.
CMD ["python", "-m", "waitress", "--host=0.0.0.0", "--port=5000", "--threads=8", "app:app"]
