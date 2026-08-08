import os

H5_MODEL = os.path.join(os.path.dirname(__file__), 'assets', 'malaria_detection_model.h5')
TFLITE_MODEL = os.path.join(os.path.dirname(__file__), 'assets', 'malaria_model.tflite')

if __name__ == '__main__':
    try:
        import tensorflow as tf
    except ImportError as e:
        raise SystemExit(
            'TensorFlow is not installed in this Python environment.\n'
            'Install it first with: python -m pip install tensorflow-cpu==2.21.0\n'
            'Then rerun this script.'
        ) from e

    if not os.path.exists(H5_MODEL):
        raise SystemExit(f'H5 model not found: {H5_MODEL}')

    print(f'Converting H5 model to TFLite:\n  {H5_MODEL}\n  {TFLITE_MODEL}')

    model = tf.keras.models.load_model(H5_MODEL)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    with open(TFLITE_MODEL, 'wb') as f:
        f.write(tflite_model)

    print('Conversion complete. TFLite model saved at:', TFLITE_MODEL)
