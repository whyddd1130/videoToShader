#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float threshould;

void main() 
{
    vec2 uv1 = textureCoord;
    vec4 res = texture2D(inputImageTexture, uv1);
    float grey = dot(res.rgb, vec3(0.299, 0.587, 0.114));
    res.rgb = step(threshould, res.rgb);
    gl_FragColor = res;
}
