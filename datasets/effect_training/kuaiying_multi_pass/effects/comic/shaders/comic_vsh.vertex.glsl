#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH


attribute vec4 vPosition;
varying vec2 vTextureCoordinates;

void main() {
    gl_Position = vPosition;
    vTextureCoordinates = (vPosition.xy + 1.0) / 2.0;
}
