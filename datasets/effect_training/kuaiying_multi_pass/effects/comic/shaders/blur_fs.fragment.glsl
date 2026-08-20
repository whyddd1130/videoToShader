#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

uniform sampler2D inputImageTexture;
//uniform vec2 sz;
varying vec2 textureCoord;
varying vec4 coord1;
varying vec4 coord2;
varying vec4 coord3;



void main() {
    vec4 result = vec4(0.0);

    result += texture2D(inputImageTexture,coord3.xy) * 0.0205;
    result += texture2D(inputImageTexture,coord2.xy) * 0.0855;
    result += texture2D(inputImageTexture,coord1.xy) * 0.232;
    result += texture2D(inputImageTexture,textureCoord) * 0.324;
    result += texture2D(inputImageTexture,coord1.zw) * 0.232;
    result += texture2D(inputImageTexture,coord2.zw) * 0.0855;
    result += texture2D(inputImageTexture,coord3.zw) * 0.0205;

    gl_FragColor = result;
}
