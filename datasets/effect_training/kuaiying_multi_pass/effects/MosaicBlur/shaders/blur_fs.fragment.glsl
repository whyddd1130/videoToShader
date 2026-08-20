#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

uniform sampler2D u_srcSampler;
varying vec2 blurCoordinates[13];

vec4 effectColor(vec2 loc) {
    return texture2D(u_srcSampler, loc);
}

void main()
{
    vec4 sum = vec4(0.0);
    sum += effectColor(blurCoordinates[0]) * 0.046118;
    sum += effectColor(blurCoordinates[1]) * 0.046118;
    sum += effectColor(blurCoordinates[2]) * 0.058552;
    sum += effectColor(blurCoordinates[3]) * 0.058552;
    sum += effectColor(blurCoordinates[4]) * 0.071181;
    sum += effectColor(blurCoordinates[5]) * 0.071181;
    sum += effectColor(blurCoordinates[6]) * 0.082860;
    sum += effectColor(blurCoordinates[7]) * 0.082860;
    sum += effectColor(blurCoordinates[8]) * 0.092356;
    sum += effectColor(blurCoordinates[9]) * 0.098568;
    sum += effectColor(blurCoordinates[10]) * 0.098568;
    sum += effectColor(blurCoordinates[11]) * 0.092356;
    sum += effectColor(blurCoordinates[12]) * 0.100731;

    gl_FragColor = sum;
}
