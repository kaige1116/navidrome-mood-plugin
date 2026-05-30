apt-get update && apt-get install -y build-essential git libyaml-dev libfftw3-dev libavcodec-dev libavformat-dev libavutil-dev libswresample-dev libsamplerate0-dev libtag1-dev libchromaprint-dev libeigen3-dev pkg-config python3-dev
pip install tensorflow==2.15.1 numpy==1.26.4
git clone --depth 1 https://github.com/MTG/essentia.git /tmp/essentia
cd /tmp/essentia
TF_DIR=$(python3 -c "import tensorflow as tf; print(tf.sysconfig.get_lib())")
TF_INC=$(python3 -c "import tensorflow as tf; print(tf.sysconfig.get_include())")
ln -sf $TF_DIR/libtensorflow_framework.so.2 /usr/local/lib/libtensorflow_framework.so
ln -sf $TF_DIR/python/_pywrap_tensorflow_internal.so /usr/local/lib/libpywrap_tensorflow_internal.so
mkdir -p /usr/local/lib/pkgconfig
echo "Name: TensorFlow" > /usr/local/lib/pkgconfig/tensorflow.pc
echo "Description: TensorFlow library" >> /usr/local/lib/pkgconfig/tensorflow.pc
echo "Version: 2.15.0" >> /usr/local/lib/pkgconfig/tensorflow.pc
echo "Cflags: -I$TF_INC" >> /usr/local/lib/pkgconfig/tensorflow.pc
echo "Libs: -L/usr/local/lib -ltensorflow_framework -lpywrap_tensorflow_internal" >> /usr/local/lib/pkgconfig/tensorflow.pc
ldconfig
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
python3 waf configure --build-static --with-python --with-tensorflow
python3 waf -j 1
