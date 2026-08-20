#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

vec2 Mirror(vec2 x) { return abs(mod(x-1., 2.)-1.); }
float cut(vec2 u) {return step(0., u.x)*step(u.x, 1.)*step(0., u.y)*step(u.y, 1.); }

uniform vec2 u_ScreenParams;
uniform float u_Complexity;
uniform float u_Evolution;
uniform float u_Cycle;
uniform float u_Brightness;
uniform float u_Contrast;
uniform float u_Range;

uniform vec2 u_Scale;
uniform vec2 u_Offset;
uniform float u_Rotate;
uniform float u_SubImpact;
uniform float u_SubScale;
uniform float u_SubRotate;
uniform vec2 u_SubOffset;
uniform float u_type;

#define PI 3.1415926
#define HASHSCALE3 vec3(.8031, .1030, .3973)
float hash21(vec2 p)
{
    vec2 p2 = fract(p*1324.518);
    p2+=dot(p2,p2.yx+22.541);
    return fract((p2.x+p2.y)*p2.y);
}

vec2 random2(vec2 p, vec2 seed)
{
    float n = hash21((p.xy));
    float n2 = 2.412;
    float evol = seed.x + n;
    float evol0 = floor(evol);
    float evol1 = evol0+1.0;
    if(u_Cycle >= 2.0)
    {
        evol0 = floor(mod(evol, u_Cycle));
        evol1 = floor(mod(evol+1.0, u_Cycle));
    }
    vec2 p2 = fract((p.xy)*(34.532+evol0*n2 + (seed.y) * HASHSCALE3.x));
    p2+=dot(p2,p2.yx+15.434);
    vec2 result1 = fract((p2.xy+p2.yx + 0.523)*p2.yx+n);

    vec2 p22 = fract((p.xy)*(34.532+evol1*n2 + (seed.y) * HASHSCALE3.x));
    p22+=dot(p22,p22.yx+15.434);
    vec2 result2 = fract((p22.xy+p22.yx + 0.523)*p22.yx+n);

    return mix(result1, result2, fract(evol)) * 2.0 - 1.0;
}

vec2 rotate(vec2 uv, float theta)
{
    uv.y *= u_ScreenParams.y / u_ScreenParams.x;
    float sint = sin(theta);
    float cost = cos(theta);
    mat2 rot = mat2(
        cost, sint,
        -sint, cost
    );
    uv -= 0.5;
    uv = rot * uv;
    uv += 0.5;
    uv.y *= u_ScreenParams.x / u_ScreenParams.y;
    return uv;
}

float interpolation(vec2 uv, vec2 seed)
{
    vec2 ratio = vec2(720.0) * u_ScreenParams.xy / min(u_ScreenParams.x, u_ScreenParams.y);
    vec2 _uv = floor(uv * ratio / 100.0);
    vec2 _fuv = fract(uv * ratio / 100.0);
    vec4 ofs = vec4(-1.0, 0.0, 1.0, 2.0);
    vec2 n4 = random2(_uv + ofs.yy, seed);
    vec2 n7 = random2(_uv + ofs.zy, seed);
    vec2 n10 = random2(_uv + ofs.yz, seed);
    vec2 n13 = random2(_uv + ofs.zz, seed);
    vec2 factor = vec2(0.0);
    factor = _fuv;
    factor = _fuv * _fuv * _fuv * (_fuv * (_fuv * 6.0 - 15.0) + 10.0);
    float ret = mix(
        mix(dot(n4, _fuv - ofs.yy), dot(n7, _fuv - ofs.zy), factor.x),
        mix(dot(n10, _fuv - ofs.yz), dot(n13, _fuv - ofs.zz), factor.x),
        factor.y
    );
    return ret * 0.5 + 0.5;
}

float gradient_noise(vec2 uv, float complexity, float evolution, float subImpact,
                    float subScale, float subRotate, float rand, vec2 subOffset)
{
    vec2 ratio = vec2(720.0) * u_ScreenParams.xy / min(u_ScreenParams.x, u_ScreenParams.y);
    float ic = floor(complexity);
    float fc = fract(complexity);
    float ie = (evolution);
    float fe = fract(evolution);
    float layer = interpolation(uv, vec2(ie, 1.0 + rand));
    float sumWeight = 1.0;
    float weight = subImpact;
    float sum = layer * 1.0;
    for (float i = 2.0; i <= 10.0; i += 1.0)
    {
        if (i > ic) break;
        uv -= subOffset / ratio;
        uv = rotate(uv, subRotate * PI / 180.0);
        uv *= subScale;

        layer = interpolation(uv, vec2(ie, 1.0 + rand)) * weight;

        sumWeight += weight;
        weight *= subImpact;
        sum += layer;
    }
    uv -= subOffset / ratio;
    uv = rotate(uv, subRotate * PI / 180.0);
    uv *= subScale;
    layer = interpolation(uv, vec2(ie, 1.0 + rand)) * weight * fc;
    sumWeight += weight * fc;
    sum += layer;
    sum /= sumWeight;
    return clamp(sum, 0.0, 1.0);
}

float colorAdjust(float c, float brightness, float contrast)
{
    c += brightness;
    if (contrast>0.0)
    {
        c = (c-0.5)*(contrast*10.0+1.0) + 0.5;
    }
    else
    {
        c = (c-0.5)*(contrast+1.0) + 0.5;
    }
    return c;
}

vec2 turblent(vec2 _u) {
    vec2 uv = _u;
    uv -= u_Offset;
    uv = rotate(uv, u_Rotate * PI / 180.0);
    uv = uv * (1. / u_Scale);

    float n1 = 0.5;
    float n2 = 0.5;
    if (u_type < 0.05)
    {
        n1 = gradient_noise(uv, clamp(u_Complexity, 1.0, 10.0), u_Evolution, u_SubImpact, 100.0 / u_SubScale, u_SubRotate, 0.0, u_SubOffset);
        n2 = gradient_noise(uv, clamp(u_Complexity, 1.0, 10.0), u_Evolution, u_SubImpact, 100.0 / u_SubScale, u_SubRotate, 2.0, u_SubOffset);
    }
    else
    {
        n1 = gradient_noise(vec2(0.5, uv.y), clamp(u_Complexity, 1.0, 10.0), u_Evolution, u_SubImpact, 100.0 / u_SubScale, u_SubRotate, 0.0, u_SubOffset);
        n2 = gradient_noise(vec2(uv.x, 0.5), clamp(u_Complexity, 1.0, 10.0), u_Evolution, u_SubImpact, 100.0 / u_SubScale, u_SubRotate, 2.0, u_SubOffset);
    }
    n1 = colorAdjust(n1, u_Brightness, u_Contrast);
    n2 = colorAdjust(n2, u_Brightness, u_Contrast);

    float ins = clamp(u_Scale.x, 0.01, 1.0) * u_Range;
    vec4 b = vec4(0.0);
    vec2 use_uv = vec2(0);
    if (u_type < 0.05) use_uv = vec2(_u.x+(n1-0.5)*ins, _u.y+(n2-0.5)*ins);
    else if (u_type < 0.15) use_uv = vec2(_u.x+(n1-0.5)*ins, _u.y);
    else if(u_type < 0.25) use_uv = vec2(_u.x, _u.y+(n2-0.5)*ins);
    else vec2(_u.x+(n1-0.5)*ins, _u.y+(n2-0.5)*ins);
    return use_uv;
}

uniform float u_fov;
uniform float u_strength;
uniform float intensity;
vec2 fov(vec2 _u)
{
    vec2 uv = _u;
    vec2 ratio = (u_ScreenParams.xy / max(u_ScreenParams.x, u_ScreenParams.y));
    float scale = max(u_ScreenParams.x / u_ScreenParams.y, u_ScreenParams.y / u_ScreenParams.x);
    for (int i = 1; i < 16; ++i)
    {
        uv -= 0.5;
        uv *= ratio;
        float d = length(uv * 2.0);
        uv = uv * pow((d*d) + 1.0, -pow(u_fov * (scale / (16. / 9.)) * u_strength * intensity * 0.0059375, 3.0));
        uv /= ratio;

        uv += 0.5;
    }
    return uv;
}

uniform float u_Intensity;
void ExposureLighten(inout vec4 col, float _intensity, float _offset, float gray_scale_correct){

    col = col * pow(0.75, -_intensity);
    col += _offset;
    col = pow(col, vec4(1.0 / gray_scale_correct));
}

void main()
{
    vec2 uv1 = textureCoord;
    uv1 = turblent(uv1);
    uv1 = fov(uv1);
    vec4 col = texture2D(inputImageTexture, (uv1));
    vec4 res = col;
    ExposureLighten(res, u_Intensity, 0., 1.);
    gl_FragColor = res;
}
