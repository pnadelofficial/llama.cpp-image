# syntax=docker/dockerfile:1
# =============================================================================
# Stage 1: Build
# Build llama.cpp from source against CUDA 12.2
# =============================================================================
ARG CUDA_VERSION=12.2.0
ARG UBUNTU_VERSION=22.04
ARG LLAMA_CPP_TAG=master

FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION} AS build

ARG LLAMA_CPP_TAG

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    cmake \
    build-essential \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Clone llama.cpp at the specified tag/branch
WORKDIR /app
RUN git clone --depth 1 --branch ${LLAMA_CPP_TAG} https://github.com/ggml-org/llama.cpp.git . || \
    git clone --depth 1 https://github.com/ggml-org/llama.cpp.git .

# Build with CUDA support
# GGML_CUDA=ON enables CUDA backend
# CMAKE_CUDA_ARCHITECTURES covers a broad range of GPU generations:
#   60/61 = Pascal, 70 = Volta, 75 = Turing, 80/86 = Ampere, 89 = Ada, 90 = Hopper
#   Narrow this down to your HPC's specific GPU arch for a faster/smaller build
RUN cmake -B build \
    -DGGML_CUDA=ON \
    -DGGML_CUDA_NO_VMM=ON \
    -DCMAKE_CUDA_ARCHITECTURES="80;86;89;90" \
    -DLLAMA_CURL=ON \
    -DCMAKE_BUILD_TYPE=Release

RUN cmake --build build --config Release -j$(nproc) || \
    (echo "BUILD FAILED" && false)

# =============================================================================
# Stage 2: Runtime
# Minimal image with only runtime CUDA libs and compiled binaries
# =============================================================================
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION} AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled binaries from build stage
COPY --from=build /app/build/bin/ /app/

# Add /app to PATH so binaries are accessible directly
ENV PATH=/app:$PATH
ENV LD_LIBRARY_PATH=/app:$LD_LIBRARY_PATH

WORKDIR /app

# Default entrypoint — override at runtime with e.g. llama-server, llama-cli, etc.
ENTRYPOINT ["/app/llama-cli", "/app/llama-server"]