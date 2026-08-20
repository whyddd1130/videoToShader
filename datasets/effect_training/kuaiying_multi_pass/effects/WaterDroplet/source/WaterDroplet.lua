
local function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end

---@language GLSL
local vs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

attribute vec2 position;
varying vec2 textureCoord;

void main()
{
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
]]

---@language GLSL
local fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

void main() 
{
    gl_FragColor = texture2D(inputImageTexture, textureCoord);
}
]]

---@language GLSL
local fs1 = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float chromatic_red;
uniform float chromatic_blue;

vec2 Mirror(vec2 x) { return abs(mod(x-1., 2.)-1.); }
float cut(vec2 u) { return step(0., u.x)*step(u.x, 1.)*step(0., u.y)*step(u.y, 1.); }

void main()
{
    vec2 uv1 = textureCoord;
    uv1 -= 0.5;
    uv1 += 0.5;
    vec4 col_r = texture2D(inputImageTexture, Mirror(vec2(uv1.x + chromatic_red, uv1.y)));
    vec4 col_g = texture2D(inputImageTexture, Mirror(vec2(uv1.x, uv1.y)));
    vec4 col_b = texture2D(inputImageTexture, Mirror(vec2(uv1.x - chromatic_blue, uv1.y)));

    vec4 res = vec4(col_r.r, col_g.g, col_b.b, max(col_r.a + col_g.a + col_b.a, 1.));
    gl_FragColor = res;
}
]]

---@language GLSL
local fs2 = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 u_ScreenParams;
uniform float blurSize;
uniform float angle;

float normpdf(in float x, in float sigma)
{
    return 0.39894*exp(-0.5*x*x/(sigma*sigma))/sigma;
}
vec4 gaussianBlur(sampler2D i_InputTex, vec2 i_Uv, float _a)
{
    float sigma = 4.0;
    float first = normpdf(0.0, sigma);
    float weight = 0.5 * 1.02 + 0.5;

    float radian = 3.1415926 * _a / 180.0;
    vec2 dir = vec2(cos(radian), sin(radian) * u_ScreenParams.x/u_ScreenParams.y);
    dir *= blurSize * 0.1;
    vec4 sum            = vec4(0.0);
    vec4 result         = vec4(0.0);
    vec2 unit_uv        = dir;
    vec4 curColor       = texture2D(i_InputTex, i_Uv);
    float gamma = 1.0;
    vec4 centerPixel    = pow(curColor, vec4(gamma))*weight;
    float sum_weight    = weight;
    const int GLOWSAMPLE = 25;
    float s = float(GLOWSAMPLE);
    for(int i=1;i<=GLOWSAMPLE;i+=1)
    {
        vec2 curRightCoordinate = i_Uv+float(i)*unit_uv;
        vec2 curLeftCoordinate  = i_Uv+float(-i)*unit_uv;
        vec4 rightColor = texture2D(i_InputTex, curRightCoordinate);
        vec4 leftColor = texture2D(i_InputTex, curLeftCoordinate);
        weight = (normpdf(float(i) / s * 15.0, sigma) / first - 0.5) * 1.02 + 0.5;
        sum+=pow(rightColor, vec4(gamma))*weight;
        sum+=pow(leftColor, vec4(gamma))*weight;
        sum_weight+=weight*2.0;
    }
    result = (sum+centerPixel)/sum_weight; 
    return pow(clamp(result, 0.0, 1.0), vec4(1.0 / gamma));
}

void main()
{
    vec2 screenSize = u_ScreenParams;
    vec2 uv1 = textureCoord;
    vec4 res = gaussianBlur(inputImageTexture, uv1, angle);
    gl_FragColor = res;
}
]]

---@language GLSL
local fs3 = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 u_Center;
uniform vec2 u_ScreenParams;
uniform float u_Amount;
uniform float u_Quality;

float normpdf(in float x, in float sigma)
{
    return 0.39894*exp(-0.5*x*x/(sigma*sigma))/sigma;
}
void main()
{
    float quality = clamp(u_Quality * 0.01, 0.1, 1.0) * 12.0;
    float amount = u_Amount * u_ScreenParams.x / 720.0;
    vec2 uv = textureCoord;
    vec2 dir = normalize(uv - u_Center);
    float x = length(uv - u_Center);
    dir = dir / u_ScreenParams.x * 8.0 * sign(amount) / quality;
    float sigma = (abs(amount) * 0.2 * quality + 1.0) * x;
    float weight = normpdf(0.0, sigma);
    vec4  res = texture2D(inputImageTexture, uv) * weight;
    float sumWeight = weight;

    float s = (quality * abs(amount) * 0.5 + 1.0) * x;

    const float maxSamples = 45.;     // Custom Value;

    for (float i = 1.0; i < maxSamples; i += 1.0)
    {
        weight = normpdf(float(i), sigma);
        vec4 tmp = (texture2D(inputImageTexture, uv - mix(1., s, (i-1.)/maxSamples) * dir)) * weight;
        res += tmp;
        sumWeight += weight;
    }
    gl_FragColor = vec4(res / sumWeight);
}
]]

---@language GLSL
local fs4 = [[
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
]]

---@language GLSL
local fs5 = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float scale;
uniform float chromatic_red;
uniform float chromatic_blue;

vec2 Mirror(vec2 x) { return abs(mod(x-1., 2.)-1.); }
float cut(vec2 u) {return step(0., u.x)*step(u.x, 1.)*step(0., u.y)*step(u.y, 1.); }

void main()
{
    vec2 uv1 = textureCoord;
    uv1 -= 0.5;
    uv1 /= scale;
    uv1 += 0.5;
    vec4 col_r = texture2D(inputImageTexture, Mirror(vec2(uv1.x + chromatic_red, uv1.y)));
    vec4 col_g = texture2D(inputImageTexture, Mirror(vec2(uv1.x, uv1.y)));
    vec4 col_b = texture2D(inputImageTexture, Mirror(vec2(uv1.x - chromatic_blue, uv1.y)));
    vec4 res = vec4(col_r.r, col_g.g, col_b.b, max(col_r.a+col_g.a+col_b.a, 1.));
    gl_FragColor = res;
}
]]

---@language GLSL
local fs6 = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 u_Center;
uniform vec2 u_ScreenParams;
uniform float u_Amount;
uniform float u_Quality;
#define PI 3.1415926
vec2 rotate(vec2 uv, vec2 center, float angle)
{
    float theta = angle * PI / 180.0;
    float sint = sin(theta), cost = cos(theta);
    uv -= center;
    uv.x *= u_ScreenParams.x/u_ScreenParams.y;
    uv = mat2(cost, sint, -sint, cost) * uv;
    uv.x /= u_ScreenParams.x/u_ScreenParams.y;
    return uv + center;
}
void main()
{
    const int SAMPLES = 32;
    float quality = clamp(u_Quality * 0.01, 0.1, 1.0) * 2.6 * u_ScreenParams.x / 720.0;
    float amount = u_Amount * 7.9;
    vec2 uv = textureCoord;
    float x = length(uv - u_Center);
    float weight = 0.0;
    vec4 res = texture2D(inputImageTexture, uv) * weight;
    float sumWeight = weight;
    float s = abs(amount) * x * quality * 0.5 + 1.0;
    float angle = 0.225;
    float a = 0.0;

    const float maxSamples = 40.;     // Custom Value;
    angle = angle * (amount) / maxSamples;
    for (float i = 0.0; i < maxSamples; i += 1.0)
    {
        weight = 1.0;
        vec2 tmpUV = rotate(uv, u_Center, -(amount) * 0.225 * 0.5 + mix(0., maxSamples, i/maxSamples) * angle);
        res += texture2D(inputImageTexture, tmpUV) * weight;
        sumWeight += weight;
    }

    gl_FragColor = vec4(res / sumWeight);
}
]]

---@language GLSL
local fs7 = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 u_ScreenParams;
uniform float scale;
uniform float rot;
uniform vec2 pos;

vec2 Mirror(vec2 x) { return abs(mod(x-1., 2.)-1.); }
float Cut(vec2 u) {return step(0., u.x)*step(u.x, 1.)*step(0., u.y)*step(u.y, 1.); }

///////////////////////  rotate ///////////////////////
const float PI = 3.1415926;
void Rotate(inout vec2 u, float a, vec2 size) {
    float r = a/180.*PI;
    u -= 0.5;
    u.x *= size.x/size.y;
    u *= mat2(cos(r), sin(r), -sin(r), cos(r));
    u.x /= size.x/size.y;
    u += 0.5;
}

////////////////////////  exposure  ////////////////////////////
uniform float u_Intensity;
void ExposureLighten(inout vec4 col, float _intensity, float _offset, float gray_scale_correct){

    col = col * pow(0.75, -_intensity);
    col += _offset;
    col = pow(col, vec4(1.0 / gray_scale_correct));
}

////////////////////////  cclens  ////////////////////////////
uniform float u_Convergence;
uniform float u_Radius;
uniform vec2 u_Center;
vec3 CCLens(vec2 _u, vec2 _center, float _radius, float _convergence, vec2 _size)
{
    vec2 center = _center;
    vec2 uv = _u - center;
    uv.x /= _size.y / _size.x;
    if(_size.y>_size.x) uv *= max(1., (_size.y/_size.x+1.)*0.55);
    float r = _radius;
    float k1 = -_convergence * 100. * 1.05 / pow(r, 2.);
    float l = length(uv);
    float r2 = l * (1.0 + k1 * pow(l, 2.));
    float theta = atan(uv.x, uv.y);
    float x = sin(theta) * r2 * 1.0;
    float y = cos(theta) * r2 * 1.0;
    uv = vec2(x, y);
    if(_size.y>_size.x) uv /= max(1., (_size.y/_size.x+1.)*0.55);
    uv.x *= _size.y / _size.x;
    uv += _center;
    return vec3(uv, l);
}

vec2 uvProtect(vec2 uv)
{
    return step(vec2(0.0), uv) * step(uv, vec2(1.0));
}

void main()
{
    vec2 uv1 = textureCoord;
    uv1 += pos;
    uv1 -= 0.5;
    uv1 /= scale;
    uv1 += 0.5;
    Rotate(uv1, -rot, u_ScreenParams.xy);
    vec3 cc_lens = CCLens(uv1, u_Center, u_Radius, u_Convergence, u_ScreenParams.xy);
    uv1 = cc_lens.xy;
    vec4 res = texture2D(inputImageTexture, uv1);
    vec2 uvp = uvProtect(uv1);
    res *= uvp.x * uvp.y * step(cc_lens.z, (u_Radius) * 0.01 + 0.01 * (u_Radius * 0.02));
    res *= Cut(uv1);
    ExposureLighten(res, u_Intensity, 0., 1.);
    gl_FragColor = res;
}
]]

---@language GLSL
local fs8 = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D frontTex;
uniform sampler2D backTex;

const float PI = 3.1415926;

float cut(vec2 u) {return step(0.,u.x)*step(u.x,1.)*step(0.,u.y)*step(u.y,1.);}
vec2 mirror(vec2 x) { return abs(mod(x+1., 2.)-1.); }

void ExposureLighten(vec4 i_col, float _alpha, out vec4 o_col){

    o_col = pow(i_col, 1./vec4(2.2)) * pow(0.75, -1.0);
    o_col += 1.0;
    o_col = pow(o_col, vec4(1.0));
    o_col = mix(i_col, o_col, _alpha);
    o_col = pow(o_col, vec4(2.2));
}

void main()
{
    vec2 uv1 = textureCoord;
    vec4 frontCol = texture2D(frontTex, mirror(uv1));
    vec2 uv2 = textureCoord;
    uv2 -= 0.5;
    uv2 += 0.5;
    vec4 backCol = texture2D(backTex, uv2) * cut(uv2);
    vec4 res = backCol;
    res = mix(frontCol, backCol, res.a);    
    gl_FragColor = res;
}
]]

local ae_attribute = {
    ["ADBE_Scale_0_0"]={
		{{0.33333333,0.33333333,0.33333333, 0,0,0.33333333, 0.45806591,0.45806591,0.66666667, 1,1,0.66666667, }, {17, 31, }, {{50, 50, 100, }, {100, 100, 100, }, }, }, 
	}, 
	["ADBE_Exposure2_0003_0_0"]={
		{{1, 0.06582312, 0.765633984, 1.204632644, }, {1, 26, }, {{0, }, {2., }, }, }, 
		{{0.644606868, 0.184062241, 0.585342733, 0.992165871, }, {26, 35, }, {{2., }, {0, }, }, }, 
	}, 
	["ADBE_Position_0_1"]={
		{{0.31236, 0, 0.088836, 1, }, {1, 15, }, {{-400, 400, 0, }, {400, 400, 0, }, }, }, 
	}, 
	["ADBE_Radial_Blur_0001_1_2"]={
		{{0.166666667, 0, 0.833333333, 1, }, {0, 8, }, {{44, }, {11, }, }, }, 
		{{0.356883983, 0, 0.740497505, 1.006195132, }, {8, 12, }, {{11, }, {4, }, }, }, 
		{{0.927405414, 0.013065947, 0.801377482, 0.994417031, }, {12, 26, }, {{4, }, {25, }, }, }, 
		{{0.213153558, -0.008730763, 0.27874318, 0.985845624, }, {26, 34.077148, }, {{25, }, {0, }, }, }, 
	}, 
	["Mettle_SkyBox_Chromatic_Aberrat_0004_1_3"]={
		{{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, {20, 30, }, {{3, }, {0, }, }, }, 
	}, 
	["Mettle_SkyBox_Chromatic_Aberrat_0006_1_4"]={
		{{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, {20, 30, }, {{10, }, {0, }, }, }, 
	}, 
	["CC_Lens_0002_1_5"]={
		{{0.646666527, 0.006471737, 0.185546759, 1, }, {15, 26, }, {{60, }, {70, }, }, }, 
		{{0.660683496, 0.008303146, 0.832867486, 0.99972499, }, {26, 33, }, {{70, }, {500, }, }, }, 
	}, 
	["ADBE_Scale_1_6"]={
		{{1,1,0.33333333, 0,0,0.33333333, 0.750639071,0.750639071,0.66666667, 1.003491483,1.003491483,0.66666667, }, {15, 28, }, {{90, 90, 100, }, {120, 120, 100, }, }, }, 
		{{0.364602248,0.364602248,0.166666667, -0.00254778,-0.00254778,0.166666667, 0.149559816,0.149559816,0.833333333, 1.01682358,1.01682358,0.833333333, }, {28, 32, }, {{120, 120, 100, }, {100, 100, 100, }, }, }, 
	}, 
	["ADBE_Rotate_Z_1_7"]={
		{{0.289108263, 0.032995518, 0.063339295, 0.08120114, }, {1, 14, }, {{-150, }, {0, }, }, }, 
		{{1, 0.242933341, 0.471450041, 0.99184884, }, {14, 31, }, {{0, }, {720, }, }, }, 
	}, 
    ["Mettle_SkyBox_Chromatic_Aberrat_0004_0_0"]={
		{{0.24336298, 0, 0.612684531, 1, }, {0, 12, }, {{0, }, {5, }, }, }, 
	}, 
	["Mettle_SkyBox_Chromatic_Aberrat_0006_0_1"]={
		{{0.297890471, 0.030956993, 0.558702274, 1.013522105, }, {0, 12, }, {{0, }, {15, }, }, }, 
	}, 
	["ADBE_Gaussian_Blur_2_0001_0_2"]={
		{{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, {0, 12, }, {{0, }, {20, }, }, }, 
	}, 
	["ADBE_Radial_Blur_0001_0_3"]={
		{{0.257881026, 0.023559498, 0.482636581, 0.947773463, }, {0, 12, }, {{0, }, {20, }, }, }, 
	}, 
	["ADBE_Optics_Compensation_0001_0_4"]={
		{{0.297890471, 0.00140469, 0.440922932, 1.002569659, }, {0, 12, }, {{0, }, {100, }, }, }, 
	}, 
	["ADBE_Exposure2_0003_0_5"]={
		{{0.442183942, 0.000739162, 0.386122833, 0.996006764, }, {0, 24, }, {{0, }, {1., }, }, }, 
	}, 
	["ADBE_Turbulent_Displace_0002_0_6"]={
		{{0.356780142, 0.007286317, 0.558702274, 1.002008233, }, {0, 12, }, {{0, }, {101, }, }, }, 
	}, 
	["ADBE_Turbulent_Displace_0003_0_7"]={
		{{0.356780142, 0.005411162, 0.558702274, 1.001491409, }, {0, 12, }, {{40, }, {176, }, }, }, 
	}, 
	["ADBE_Turbulent_Displace_0005_0_8"]={
		{{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, {0, 12, }, {{1, }, {1.5, }, }, }, 
	}, 
	["ADBE_Turbulent_Displace_0006_0_9"]={
		{{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, {2, 32, }, {{0, }, {180, }, }, }, 
	},
}

local AETools = AETools or {}
AETools.__index = AETools

function AETools.new(attrs)
    local self = setmetatable({}, AETools)
    self.attrs = attrs

    local max_frame = 0
    local min_frame = 100000
    for _,v in pairs(attrs) do
        for i = 1, #v do
            local content = v[i]
            local cur_frame_min = content[2][1]
            local cur_frame_max = content[2][2]
            max_frame = math.max(cur_frame_max, max_frame)
            min_frame = math.min(cur_frame_min, min_frame)
        end
    end

    self.all_frame = max_frame - min_frame
    self.min_frame = min_frame

    return self
end

function AETools._remap01(a,b,x)
    if x < a then return 0 end
    if x > b then return 1 end
    return (x-a)/(b-a)
end

function AETools._cubicBezier(p1, p2, p3, p4, t)
    return {
        p1[1]*(1.-t)*(1.-t)*(1.-t) + 3*p2[1]*(1.-t)*(1.-t)*t + 3*p3[1]*(1.-t)*t*t + p4[1]*t*t*t,
        p1[2]*(1.-t)*(1.-t)*(1.-t) + 3*p2[2]*(1.-t)*(1.-t)*t + 3*p3[2]*(1.-t)*t*t + p4[2]*t*t*t,
    }
end

function AETools:_cubicBezier01(_bezier_val, p)
    local x = self:_getBezier01X(_bezier_val, p)
    return self._cubicBezier(
        {0,0},
        {_bezier_val[1], _bezier_val[2]},
        {_bezier_val[3], _bezier_val[4]},
        {1,1},
        x
    )[2]
end

function AETools:_getBezier01X(_bezier_val, x)
    local ts = 0
    local te = 1
    -- divide and conque
    repeat
        local tm = (ts+te)*0.5
        local value = self._cubicBezier(
            {0,0},
            {_bezier_val[1], _bezier_val[2]},
            {_bezier_val[3], _bezier_val[4]},
            {1,1},
            tm)
        if(value[1]>x) then
            te = tm
        else
            ts = tm
        end
    until(te-ts < 0.0001)

    return (te+ts)*0.5
end

function AETools._mix(a, b, x)
    return a * (1-x) + b * x
end

function AETools:GetVal(_name, _progress)
    local content = self.attrs[_name]
    if content == nil then
        return nil
    end

    local cur_frame = _progress * self.all_frame + self.min_frame

    for i = 1, #content do
        local info = content[i]
        local start_frame = info[2][1]
        local end_frame = info[2][2]
        if cur_frame >= start_frame and cur_frame < end_frame then
            local cur_progress = self._remap01(start_frame, end_frame, cur_frame)
            local bezier = info[1]
            local value_range = info[3]

            if #bezier > 4 then
                -- currently scale attrs contains more than 4 bezier values
                local res = {}
                for k = 1, 3 do
                    local cur_bezier = {bezier[k], bezier[k+3], bezier[k+3*2], bezier[k+3*3]}
                    local p = self:_cubicBezier01(cur_bezier, cur_progress)
                    res[k] = self._mix(value_range[1][k], value_range[2][k], p)
                end
                return res

            else
                local p = self:_cubicBezier01(bezier, cur_progress)

                if type(value_range[1]) == "table" then
                    local res = {}
                    for j = 1, #value_range[1] do
                        res[j] = self._mix(value_range[1][j], value_range[2][j], p)
                    end
                    return res
                end
                return self._mix(value_range[1], value_range[2], p)
            end

        end
    end

    local first_info = content[1]
    local start_frame = first_info[2][1]
    if cur_frame<start_frame then
        return first_info[3][1]
    end

    local last_info = content[#content]
    local end_frame = last_info[2][2]
    if cur_frame>=end_frame then
        return last_info[3][2]
    end

    return nil
end


WaterDroplet = {}

function WaterDroplet:matchWithId(effectId)
    return 'KFM KSkr WaterDroplet' == effectId
end

function WaterDroplet.createWithId(effectId)
    if not WaterDroplet:matchWithId(effectId) then
        return nil
    end
    local o = {
        program1 = {},
        program2 = {},
        program3 = {},
        program4 = {},
        program5 = {},
        program6 = {},
        program7 = {},
        program8 = {},
        currentWidth = 0,
        currentHeight = 0,
        speed = 0.0,
        progress = 0,
        attrs = {}
    }
    o = newObject(o, WaterDroplet)
    o:init()
    return o;
end

function WaterDroplet:init()
    self.program1 = CGE.ProgramObject()
    self.program1:bindAttribLocation('position', 0)
    self.program1:initWithShaderStrings(vs, fs1)
    self.program1:bind()
    self.program1:sendUniformi('inputImageTexture', 0)

    self.program2 = CGE.ProgramObject()
    self.program2:bindAttribLocation('position', 0)
    self.program2:initWithShaderStrings(vs, fs2)
    self.program2:bind()
    self.program2:sendUniformi('inputImageTexture', 0)

    self.program3 = CGE.ProgramObject()
    self.program3:bindAttribLocation('position', 0)
    self.program3:initWithShaderStrings(vs, fs3)
    self.program3:bind()
    self.program3:sendUniformi('inputImageTexture', 0)

    self.program4 = CGE.ProgramObject()
    self.program4:bindAttribLocation('position', 0)
    self.program4:initWithShaderStrings(vs, fs4)
    self.program4:bind()
    self.program4:sendUniformi('inputImageTexture', 0)

    self.program5 = CGE.ProgramObject()
    self.program5:bindAttribLocation('position', 0)
    self.program5:initWithShaderStrings(vs, fs5)
    self.program5:bind()
    self.program5:sendUniformi('inputImageTexture', 0)

    self.program6 = CGE.ProgramObject()
    self.program6:bindAttribLocation('position', 0)
    self.program6:initWithShaderStrings(vs, fs6)
    self.program6:bind()
    self.program6:sendUniformi('inputImageTexture', 0)

    self.program7 = CGE.ProgramObject()
    self.program7:bindAttribLocation('position', 0)
    self.program7:initWithShaderStrings(vs, fs7)
    self.program7:bind()
    self.program7:sendUniformi('inputImageTexture', 0)

    self.program8 = CGE.ProgramObject()
    self.program8:bindAttribLocation('position', 0)
    self.program8:initWithShaderStrings(vs, fs8)
    self.program8:bind()
    self.program8:sendUniformi('frontTex', 0)
    self.program8:sendUniformi('backTex', 1)

    local buffer = {}
    glGenBuffers(1,buffer)
    self.vertexBuffer = buffer[1]
    local vertices = {-1,-1,1,-1,-1,1,1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)

    self.attrs = AETools.new(ae_attribute)
end

function WaterDroplet:updateValue(index, val1, val2, val3)
    if index == 1 then
        -- Progress
        self.progress = val1 / 100.0
    elseif index == 2 then
        self.radius = val1 / 75.0
    elseif index == 3 then
        self.backgroundBlurSize = val1 / 20.0
    elseif index == 4 then
        self.chromaticIntensity = val1 / 50.0
    end
end

function WaterDroplet:resize(width, height)

end

function WaterDroplet:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height
end

function WaterDroplet:remap01(a,b,x)
    if x < a then return 0 end
    if x > b then return 1 end
    return (x-a)/(b-a)
end

function WaterDroplet:mix(a, b, x)
    return a * (1-x) + b * x
end

function WaterDroplet:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    local p = self.progress
    local chromatic_red = self.attrs:GetVal("Mettle_SkyBox_Chromatic_Aberrat_0004_0_0", p)[1]
    chromatic_red = chromatic_red * 0.002
    local chromatic_blue = self.attrs:GetVal("Mettle_SkyBox_Chromatic_Aberrat_0006_0_1", p)[1]
    chromatic_blue = chromatic_blue * 0.002

    --- draw4
    local fbo1 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo1:bind()
    self.program1:bind()
    self.program1:sendUniformf('chromatic_red', chromatic_red * self.chromaticIntensity)
    self.program1:sendUniformf('chromatic_blue', chromatic_blue * self.chromaticIntensity)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local blurSize = self.attrs:GetVal("ADBE_Gaussian_Blur_2_0001_0_2", p)[1]
    blurSize = blurSize * 0.0003
    --- draw5
    local fbo2 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo2:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth, self.currentHeight)
    self.program2:sendUniformf('blurSize', blurSize * self.backgroundBlurSize)
    self.program2:sendUniformf('angle', 0.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw6
    fbo1:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth, self.currentHeight)
    self.program2:sendUniformf('blurSize', blurSize * self.backgroundBlurSize)
    self.program2:sendUniformf('angle', 90.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local u_Amount = self.attrs:GetVal("ADBE_Radial_Blur_0001_0_3", p)[1]
    u_Amount = u_Amount * 2.5
    --- draw7
    fbo2:bind()
    self.program3:bind()
    self.program3:sendUniformf('u_ScreenParams', self.currentWidth, self.currentHeight)
    self.program3:sendUniformf('u_Center', 0.5, 0.5)
    self.program3:sendUniformf('u_Amount', u_Amount)
    self.program3:sendUniformf('u_Quality', 10.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local u_Complexity = self.attrs:GetVal("ADBE_Turbulent_Displace_0005_0_8", p)[1]
    local u_Evolution = self.attrs:GetVal("ADBE_Turbulent_Displace_0006_0_9", p)[1]
    u_Evolution = u_Evolution * 0.006
    local u_Contrast = self.attrs:GetVal("ADBE_Turbulent_Displace_0002_0_6", p)[1]
    local u_strength = self.attrs:GetVal("ADBE_Optics_Compensation_0001_0_4", p)[1]
    u_strength = u_strength * 0.012
    local u_Intensity = self.attrs:GetVal("ADBE_Exposure2_0003_0_5", p)[1]
    --- draw8 
    fbo1:bind()
    self.program4:bind()
    self.program4:sendUniformf('u_ScreenParams', self.currentWidth, self.currentHeight)
    self.program4:sendUniformf('u_Complexity', u_Complexity)
    self.program4:sendUniformf('u_Evolution', u_Evolution)
    self.program4:sendUniformf('u_Cycle', 0.0)
    self.program4:sendUniformf('u_Brightness', 0.0)
    self.program4:sendUniformf('u_Contrast', u_Contrast * 0.004)
    self.program4:sendUniformf('u_Range', u_Contrast * 0.003)
    self.program4:sendUniformf('u_Scale', 4.0, 4.0)
    self.program4:sendUniformf('u_Offset', -0.5, -0.5)
    self.program4:sendUniformf('u_Rotate', 0.0)
    self.program4:sendUniformf('u_SubImpact', 0.6)
    self.program4:sendUniformf('u_SubScale', 56.0)
    self.program4:sendUniformf('u_SubRotate', 0.0)
    self.program4:sendUniformf('u_SubOffset', 0.0, 0.0)
    self.program4:sendUniformf('u_type', 0.0)
    self.program4:sendUniformf('u_fov', 100.0)
    self.program4:sendUniformf('u_strength', u_strength)
    self.program4:sendUniformf('intensity', 1.0)
    self.program4:sendUniformf('u_Intensity', u_Intensity)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local scale1 = self.attrs:GetVal("ADBE_Scale_0_0", p)[1]
    scale1 = scale1 * 0.01
    chromatic_blue = self.attrs:GetVal("Mettle_SkyBox_Chromatic_Aberrat_0006_1_4", p)[1]
    chromatic_red = self.attrs:GetVal("Mettle_SkyBox_Chromatic_Aberrat_0004_1_3", p)[1]
    --- draw9
    local fbo6 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo6:bind()
    self.program5:bind()
    self.program5:sendUniformf('scale', scale1)
    self.program5:sendUniformf('chromatic_red', chromatic_red * 0.002)
    self.program5:sendUniformf('chromatic_blue', chromatic_blue * 0.002)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    u_Amount = self.attrs:GetVal("ADBE_Radial_Blur_0001_1_2", p)[1]
    --- draw10
    fbo2:bind()
    self.program6:bind()
    self.program6:sendUniformf('u_ScreenParams', self.currentWidth, self.currentHeight)
    self.program6:sendUniformf('u_Center', 0.5, 0.5)
    self.program6:sendUniformf('u_Amount', u_Amount * 0.5)
    self.program6:sendUniformf('u_Quality', 10.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo6:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local scale2 = self.attrs:GetVal("ADBE_Scale_1_6", p)[1]
    scale2 = scale2 * 0.01
    local rot = self.attrs:GetVal("ADBE_Rotate_Z_1_7", p)[1]
    local pos = self.attrs:GetVal("ADBE_Position_0_1", p)
    pos = {-(pos[1]/800-0.5), pos[2]/800-0.5}
    u_Intensity = self.attrs:GetVal("ADBE_Exposure2_0003_0_0", p)[1]
    local u_Radius = self.attrs:GetVal("CC_Lens_0002_1_5", p)[1]
    local convergence = self:remap01(28/34, 1, p)
    convergence = self:mix(44, 0, convergence)
    --- draw11
    local fbo3 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo3:bind()
    self.program7:bind()
    self.program7:sendUniformf('u_ScreenParams', self.currentWidth, self.currentHeight)
    self.program7:sendUniformf('scale', scale2)
    self.program7:sendUniformf('rot', rot)
    self.program7:sendUniformf('pos', pos[1], pos[2])
    self.program7:sendUniformf('u_Intensity', u_Intensity)
    self.program7:sendUniformf('u_Convergence', convergence * 2.0)
    self.program7:sendUniformf('u_Radius', u_Radius * 0.75 * self.radius)
    self.program7:sendUniformf('u_Center', 0.5, 0.5)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw12
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    glViewport(0, 0, self.currentWidth, self.currentHeight)
    self.program8:bind()
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, fbo3:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    AESP:recycleCachedFrameBuffer(fbo1)   
    AESP:recycleCachedFrameBuffer(fbo2)   
    AESP:recycleCachedFrameBuffer(fbo3) 
    AESP:recycleCachedFrameBuffer(fbo6)   
end

function WaterDroplet:onDestroy()
    glDeleteBuffers(1, {self.vertexBuffer})
end
    