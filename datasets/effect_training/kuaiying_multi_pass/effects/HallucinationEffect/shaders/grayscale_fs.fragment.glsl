#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

vec3 grayscaleMix(vec3 color, float strength)
{
    float gray = dot(color, vec3(0.299, 0.587, 0.114));
    return mix(color, vec3(gray), strength);
}

vec4 grayscaleMixRGBA(vec4 rgba, float strength)
{
    return vec4(grayscaleMix(rgba.rgb, strength), rgba.a);
}

vec4 unpackFloatToRGBA(inout float value)
{
    vec4 rgba;
    value *= 255.0;
    rgba.r = floor(value) * (1.0 / 255.0);
    value = fract(value);
    value *= 255.0;
    rgba.g = floor(value) * (1.0 / 255.0);
    value = fract(value);
    value *= 255.0;
    rgba.b = floor(value) * (1.0 / 255.0);
    value = fract(value);
    rgba.a = value;
    return rgba;
}

void main()
{
    vec4 srcColor = texture2D(inputImageTexture, textureCoord);
    vec4 grayColor = grayscaleMixRGBA(srcColor, 1.0);
    float packedValue = grayColor.r;
    vec4 finalColor = unpackFloatToRGBA(packedValue);
    gl_FragColor = finalColor;
}
