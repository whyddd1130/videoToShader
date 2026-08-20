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
