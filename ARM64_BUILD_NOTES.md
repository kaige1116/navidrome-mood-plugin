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

### 6. Missing Runtime Dependencies & NumPy 2.0 Conflict
*   **Action:** 
    1.  Added missing runtime libraries (`libyaml-0-2`, `libfftw3-3`, `libtag1v5`, `libchromaprint1`, `libsamplerate0`) to the `base` Docker stage so they persist in the final image.
    2.  Locked `numpy<2.0` in `requirements.txt` and ensured ARM64 build explicitly uses `numpy==1.26.4` to avoid breaking TensorFlow 2.15.1.
    3.  Improved health check error reporting in `app.py` to capture the specific `ImportError` message.
*   **Status:** Pending verification. These changes address the "essentia not installed" error which was likely caused by missing shared libraries or a broken TensorFlow/NumPy environment.

### 7. TensorFlow Library Linkage & Persistence
*   **Action:** 
    1.  Changed library linking from `ln -sf` (symlinks) to `cp` (copy) for TensorFlow shared libraries in the builder stage. This ensures they are actual files in `/usr/local/lib` rather than pointers to the transient Python site-packages folder.
    2.  Explicitly copied site-packages and specific `/usr/local` subfolders to the final image stage to ensure all Python dependencies (TF, NumPy) are preserved.
*   **Status:** Pending verification. This addresses the `libtensorflow_framework.so.2: No such file or directory` error found during local testing.

### 8. Undefined Symbol: TF_DeleteSession
*   **Action:** 
    1.  Ensured `ldconfig` is run *before* the Essentia build so the linker can find the TensorFlow libraries we copied.
    2.  Updated the `tensorflow.pc` (pkg-config) file to use standard variable structures and ensure the correct include and library paths are referenced.
    3.  Removed `--build-static` from `waf configure`.
    4.  **Added explicit `LDFLAGS`** (`-ltensorflow_framework -lpywrap_tensorflow_internal`) during the `waf` build phase. This forces the linker to resolve the TensorFlow symbols and record the dependency in `libessentia.so`.
*   **Status:** Pending verification. This addresses the runtime error where Essentia fails to load due to missing TensorFlow C++ symbols.

### 9. Missing libtensorflow_cc.so.2
*   **Action:** 
    1.  Updated the Dockerfile to use `find` to copy **all** TensorFlow-related shared libraries from the pip package to `/usr/local/lib`. This ensures architecture-specific libraries like `libtensorflow_cc.so.2` (which appeared in the ARM64 build) are included.
    2.  Implemented dynamic discovery of these libraries during the build to automatically add `-ltensorflow_cc` to the linker flags if the library is present.
    3.  Updated the final stage to robustly recreate symlinks for all possible TensorFlow library variations.
*   **Status:** Pending verification. This addresses the runtime error where `libessentia.so` was looking for `libtensorflow_cc.so.2`.

### 10. Missing Vendored Libraries (e.g., libomp)
*   **Action:** 
    1.  Updated the Dockerfile to **exhaustively find and copy ALL** shared libraries (`.so`) from the entire Python `site-packages` directory into `/usr/local/lib`.
    2.  This ensures that hidden dependencies like `libomp-54bf90fd.so.5` (which are often bundled deep within subdirectories of wheels like NumPy or TensorFlow) are successfully moved to the system path and registered with `ldconfig`.
*   **Status:** Pending verification. This addresses the stubborn `libomp: No such file or directory` error.

## Next Steps if Build Fails Again
If the current "Hardcoded Paths" commit fails, the next logical steps for debugging are:
1.  **Check the logs:** If it fails during `waf configure`, it means the hardcoded paths might be slightly different on ARM64 vs AMD64 (though unlikely for standard pip).
2.  **Verify the Wheel Contents:** Download the exact ARM64 wheel (`tensorflow_cpu_aws-2.15.1-cp311-cp311-manylinux_2_17_aarch64.manylinux2014_aarch64.whl`) and extract it to verify the exact location of `_pywrap_tensorflow_internal.so`. (Local testing showed it is inside `tensorflow/python/`).
3.  **Alternative Approach (The Nuclear Option):** If Essentia simply refuses to compile cleanly against the PyPI TensorFlow package on ARM64, the final fallback is to drop the attempt to compile Essentia from source in our Dockerfile. Instead, we would need to find a community-maintained Docker image or wheel that already has `essentia-tensorflow` compiled for ARM64 and base our image on that, or instruct ARM users to use a completely different inference backend (which would require plugin code changes).
