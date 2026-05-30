FROM python:3.11-slim AS base
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# AMD64 Build Stage
FROM base AS build-amd64
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ARM64 Build Stage
FROM base AS build-arm64
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git libyaml-dev libfftw3-dev libavcodec-dev \
    libavformat-dev libavutil-dev libswresample-dev libsamplerate0-dev \
    libtag1-dev libchromaprint-dev libeigen3-dev pkg-config python3-dev && \
    rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir "tensorflow<2.16" "numpy<2" && \
    grep -v "essentia-tensorflow" requirements.txt > req_arm.txt && \
    pip install --no-cache-dir -r req_arm.txt && \
    git clone --depth 1 https://github.com/MTG/essentia.git /tmp/essentia && \
    cd /tmp/essentia && \
    # Create a python script to handle the symlinks to avoid shell escaping issues
    echo 'import tensorflow as tf' > link_tf.py && \
    echo 'import os' >> link_tf.py && \
    echo 'tf_lib = tf.sysconfig.get_lib()' >> link_tf.py && \
    echo 'tf_inc = tf.sysconfig.get_include()' >> link_tf.py && \
    echo 'os.system(f"ln -sf {tf_lib}/libtensorflow_framework.so.2 /usr/local/lib/libtensorflow_framework.so")' >> link_tf.py && \
    echo 'os.system(f"ln -sf {tf_lib}/python/_pywrap_tensorflow_internal.so /usr/local/lib/libpywrap_tensorflow_internal.so")' >> link_tf.py && \
    echo 'os.system("mkdir -p /usr/local/lib/pkgconfig")' >> link_tf.py && \
    echo 'with open("/usr/local/lib/pkgconfig/tensorflow.pc", "w") as f:' >> link_tf.py && \
    echo '    f.write(f"Name: TensorFlow\\nDescription: TensorFlow library\\nVersion: 2.15.0\\nCflags: -I{tf_inc}\\nLibs: -L/usr/local/lib -ltensorflow_framework -lpywrap_tensorflow_internal\\n")' >> link_tf.py && \
    python3 link_tf.py && \
    ldconfig && \
    export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig && \
    python3 waf configure --build-static --with-python --with-tensorflow && \
    python3 waf -j 1 && \
    python3 waf install && \
    cd /app && rm -rf /tmp/essentia

# Select the appropriate build stage based on TARGETARCH
ARG TARGETARCH
FROM build-${TARGETARCH} AS builder

# Final stage
FROM base
COPY --from=builder /usr/local /usr/local
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
