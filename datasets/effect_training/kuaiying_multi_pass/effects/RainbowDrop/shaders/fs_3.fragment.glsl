#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;

uniform float alpha;
uniform float s;
uniform float iTime;

uniform sampler2D sdfTexture;
uniform sampler2D waterEdgeTexture;
uniform sampler2D oriTexture;

uniform vec2 screenParams;

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
vec3 blendNormal(vec3 base, vec3 blend)
{
    return blend;
}
vec3 blendNormal(vec3 base, vec3 blend, float opacity)
{
    return (blendNormal(base, blend) * opacity + blend * (1.0 - opacity));
}
float blendAdd(float base, float blend)
{
    return min(base + blend, 1.0);
}
vec3 blendAdd(vec3 base, vec3 blend)
{
    return min(base + blend, vec3(1.0));
}

vec3 blendFunc(vec3 base, vec3 blend, float opacity, int blendMode)
{
    if (blendMode == 0)
        return (blendNormal(base, blend) * opacity + base * (1.0 - opacity));
    else if (blendMode == 1)
        return (blendAdd(base, blend) * opacity + base * (1.0 - opacity));
    else
        return base;
}

vec2 lowPrecision(vec4 myuv)
{
    return myuv.xy + myuv.zw / 255.;
}

vec3 light(vec3 col, float ins)
{
    float mylight = ins;
    mylight *= 2.;
    float flag = 1.0 + mylight;
    return clamp(1.0 - pow(1. - col.rgb, vec3(flag)), 0.0, 1.0);
}

void main()
{
    float v = 0.6;

    vec4 waterEdgeCol = texture2D(waterEdgeTexture, textureCoord);
    vec4 sdfCol = texture2D(sdfTexture, textureCoord);
    vec2 sdfVec = lowPrecision(sdfCol);
    float sdf = sdfVec.x - sdfVec.y;
    vec4 oriCol = texture2D(oriTexture, textureCoord);
    float blurMask = smoothstep(-0.2, -0.1, sdf) * smoothstep(0.1, 0.00, sdf);
    vec4 resultcol = mix(oriCol, waterEdgeCol, blurMask);
    float lightMask = smoothstep(-0.2, -0.0, sdf) * smoothstep(0.15, -0.1, sdf);
    vec2 normalUV = textureCoord - 0.5;
    float d = length(normalUV);
    float angle = atan(normalUV.x, normalUV.y);
    float gray = dot(waterEdgeCol.rgb, vec3(0.299, 0.587, 0.114));
    float h = fract(gray + 0.4 * sin(angle * 2.));
    vec3 hsv = vec3(h, s, v);
    vec3 glitchCol = hsv2rgb(hsv);
    vec3 blendColLight = blendFunc(light(resultcol.rgb, 0.5), glitchCol.rgb, 1.0, 1);
    vec3 blendColDark = blendFunc(light(resultcol.rgb, 0.5), glitchCol.rgb / v, 1.0, 0);
    vec3 blendCol = mix(blendColDark, blendColLight, gray);
    resultcol.rgb = mix(resultcol.rgb, blendCol, lightMask * alpha);
    vec2 newUV = textureCoord - 0.5;
    if (screenParams.x < screenParams.y)
        newUV.y *= screenParams.y / screenParams.x;
    else
        newUV.x *= screenParams.x / screenParams.y;
    resultcol = mix(oriCol, resultcol, smoothstep(0.0, 0.5, iTime) * smoothstep(0.00, 0.2, length(newUV)));
    gl_FragColor = vec4(resultcol);
}
