#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float u_highlightParam;
uniform float u_shadowParam;

vec3 highlight(vec3 rgb, float p)
{
    vec3 inv = vec3(1.0) - rgb;
    vec3 sqr = inv * inv;
    return (vec3(1.0) - pow(inv, vec3(p))) - ((sqr - sqr * inv) * (p - 1.0));
}

vec3 shadow(vec3 rgb, float p)
{
    vec3 sqr = rgb * rgb;
    return pow(rgb, vec3(p)) + ((sqr - sqr * rgb) * (p - 1.0));
}

void main()
{
    vec4 src = texture2D(inputImageTexture, textureCoord);
    vec4 outColor = src;
    outColor.rgb = highlight(outColor.rgb, u_highlightParam);
    outColor.rgb = shadow(outColor.rgb, u_shadowParam);
    gl_FragColor = clamp(outColor, vec4(0.0), vec4(1.0));
}
