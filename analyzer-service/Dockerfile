FROM python:3.11-slim AS base

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Builder stage for architecture-specific installation
FROM base AS builder
ARG TARGETARCH

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential git libyaml-dev libfftw3-dev libavcodec-dev \
        libavformat-dev libavutil-dev libswresample-dev libsamplerate0-dev \
        libtag1-dev libchromaprint-dev libeigen3-dev pkg-config python3-dev && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Architecture-specific installation
# For arm64, we must build essentia from source as no wheels are available on PyPI
RUN if [ "$TARGETARCH" = "arm64" ]; then \
        pip install --no-cache-dir tensorflow && \
        grep -v "essentia-tensorflow" requirements.txt > req_arm.txt && \
        pip install --no-cache-dir -r req_arm.txt && \
        git clone --depth 1 https://github.com/MTG/essentia.git /tmp/essentia && \
        cd /tmp/essentia && \
        ./src/3rdparty/tensorflow/setup_from_python.sh && \
        python3 waf configure --build-static --with-python --with-tensorflow && \
        python3 waf && \
        python3 waf install && \
        cd /app && rm -rf /tmp/essentia; \
    else \
        pip install --no-cache-dir -r requirements.txt; \
    fi

# Final stage
FROM base

# Copy installed python packages and libraries from builder
COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /usr/local/bin /usr/local/bin
RUN ldconfig

# Download Essentia TF mood models
RUN mkdir -p /app/models && \
    wget -q -P /app/models https://essentia.upf.edu/models/feature-extractors/discogs-effnet/discogs-effnet-bs64-1.pb && \
    wget -q -P /app/models https://essentia.upf.edu/models/classification-heads/mood_happy/mood_happy-discogs-effnet-1.pb && \
    wget -q -P /app/models https://essentia.upf.edu/models/classification-heads/mood_sad/mood_sad-discogs-effnet-1.pb && \
    wget -q -P /app/models https://essentia.upf.edu/models/classification-heads/mood_relaxed/mood_relaxed-discogs-effnet-1.pb && \
    wget -q -P /app/models https://essentia.upf.edu/models/classification-heads/mood_aggressive/mood_aggressive-discogs-effnet-1.pb && \
    wget -q -P /app/models https://essentia.upf.edu/models/classification-heads/mood_party/mood_party-discogs-effnet-1.pb && \
    wget -q -P /app/models https://essentia.upf.edu/models/classification-heads/danceability/danceability-discogs-effnet-1.pb

COPY app.py /app/app.py
WORKDIR /app

EXPOSE 8000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
