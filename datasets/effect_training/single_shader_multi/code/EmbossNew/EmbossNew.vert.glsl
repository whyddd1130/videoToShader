precision highp float;

attribute vec2 position;
varying vec2 textureCoord;

void main() {
    gl_Position = vec4(position, 0.0, 1.0);
    textureCoord = position * 0.5 + 0.5;
}
