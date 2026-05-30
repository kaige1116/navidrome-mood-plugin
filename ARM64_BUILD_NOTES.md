# ARM64 Build Status & Debugging Notes

## The Goal
To update the `navidrome-mood-plugin` to support `arm64` (Raspberry Pi), specifically the `analyzer-service` Docker image.

## The Core Problem
The `essentia-tensorflow` pip package does **not** provide pre-built `arm64` wheels for Linux on PyPI. Running `pip install essentia-tensorflow` on an ARM64 host (like a Raspberry Pi) fails. Therefore, we must compile `essentia` from source inside the Dockerfile for the `arm64` architecture.

## Progression of Fixes & Encountered Issues

### 1. Initial Attempt: Basic Multi-Arch & Compilation
*   **Action:** Split the Dockerfile to use a `builder` stage, compiling Essentia from source using their `setup_from_python.sh` script when `TARGETARCH=arm64`. Enabled QEMU in GitHub Actions.
*   **Result (Failure):** The GitHub Action timed out or ran out of memory. Emulating ARM64 compilation via QEMU on x64 runners is extremely slow and resource-intensive.

### 2. Native Runners & TensorFlow Compatibility
*   **Action:** Switched the GitHub Action runner to `ubuntu-24.04-arm` to build natively. Limited compilation threads (`waf -j 1`).
*   **Result (Failure):** The native build completed the initial steps but failed during the `waf` compilation.
*   **Root Cause:** The default `pip install tensorflow` installed TF 2.16+, which introduced breaking changes to the C++ API, breaking Essentia's bindings.
*   **Fix Applied:** Locked TensorFlow to `< 2.16` (`tensorflow==2.15.1`) and `numpy==1.26.4`.

### 3. The `setup_from_python.sh` Linker Issue
*   **Action:** Pushed the version-locked pip dependencies.
*   **Result (Failure):** The `waf` linker failed with: `/usr/bin/ld: cannot find -lpywrap_tensorflow_internal: No such file or directory`.
*   **Root Cause:** The official Essentia helper script (`setup_from_python.sh`) relies on hardcoded paths and library names that do not match the actual layout of the PyPI `tensorflow==2.15.1` package on modern Python 3.11.

### 4. Manual Library Linking & Shell Escaping Nightmares
*   **Action:** Removed `setup_from_python.sh`. Replaced it with Docker `RUN` commands to manually find the TF libraries (`tf.sysconfig.get_lib()`), create symlinks (`ln -sf`), and generate a `pkg-config` file (`tensorflow.pc`) so `waf` could find them.
*   **Result (Failures):** Multiple subsequent builds failed immediately or during the shell execution step.
*   **Root Causes:** 
    *   Using Python `f""` strings inside `echo` statements caused Docker/Bash syntax errors due to newline `\n` escaping conflicts.
    *   Attempting to use `$(python3 -c "...")` subshells to get the dynamic paths failed silently because Docker's `/bin/sh` does not always handle subshells with nested quotes correctly, resulting in empty variables and broken symlinks.

### 5. Current State: Hardcoded Paths (The "Bulletproof" Attempt)
*   **Action:** Since the base image is strictly `python:3.11-slim`, the PyPI installation paths are deterministic. Ripped out all dynamic Python evaluation and subshells.
*   **Current Dockerfile Logic (ARM64):**
    1. Installs build dependencies.
    2. `pip install tensorflow==2.15.1 numpy==1.26.4`
    3. Clones Essentia.
    4. **Hardcoded Symlinks:** Directly links `/usr/local/lib/python3.11/site-packages/tensorflow/libtensorflow_framework.so.2` (and the `pywrap` library) to `/usr/local/lib/`.
    5. **Hardcoded pkg-config:** Uses simple `echo "..." >>` commands to write `tensorflow.pc` line-by-line, pointing `Cflags` to the hardcoded `include` directory.
    6. Runs `waf configure` and `waf install`.

## Next Steps if Build Fails Again
If the current "Hardcoded Paths" commit fails, the next logical steps for debugging are:
1.  **Check the logs:** If it fails during `waf configure`, it means the hardcoded paths might be slightly different on ARM64 vs AMD64 (though unlikely for standard pip).
2.  **Verify the Wheel Contents:** Download the exact ARM64 wheel (`tensorflow_cpu_aws-2.15.1-cp311-cp311-manylinux_2_17_aarch64.manylinux2014_aarch64.whl`) and extract it to verify the exact location of `_pywrap_tensorflow_internal.so`. (Local testing showed it is inside `tensorflow/python/`).
3.  **Alternative Approach (The Nuclear Option):** If Essentia simply refuses to compile cleanly against the PyPI TensorFlow package on ARM64, the final fallback is to drop the attempt to compile Essentia from source in our Dockerfile. Instead, we would need to find a community-maintained Docker image or wheel that already has `essentia-tensorflow` compiled for ARM64 and base our image on that, or instruct ARM users to use a completely different inference backend (which would require plugin code changes).
