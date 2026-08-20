# Put your model here

This example expects a MobileFaceNet TFLite model at:

    assets/mobilefacenet.tflite

with a 112x112x3 float input and a 192-d output — the same shape the package's
`FaceRecognizer` uses. No model ships with the package or this example: a
pre-trained `.tflite`'s weights carry their own license, and many copies online
have none at all. See the package README's "Model & license" section.

The whole `assets/` folder is declared in `pubspec.yaml`, so dropping the file
in here is all that is needed — no pubspec edit.

Optionally add `assets/antispoof.tflite` (e.g. a MiniFASNet) and set
`passiveSpoofEnabled: true` to exercise `SpoofDetector`.
