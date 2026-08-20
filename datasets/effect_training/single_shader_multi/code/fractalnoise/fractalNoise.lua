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
    textureCoord = position*.5+.5;
    gl_Position = vec4(position, 0.,1.);
}
]]

---@language GLSL
local fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

uniform sampler2D inputImageTexture;
varying vec2 textureCoord;

uniform vec2 center;

/*
 * 分流类型
 * 0: basic
 * 1: turbulent smooth
 * 2: turbulent basic
 * 3: turbulent sharp
 * 4: dynamic
 */
uniform int fractalType;
/*
 * 杂色类型
 * 0: block
 * 1: linear
 * 2: softlinear
 * 3: spline
 */
uniform int noiseType;
//反转
const bool invert = false;
//对比度
uniform float contrast;
//亮度
uniform float brightness;
/*
 * 溢出
 * 0: clip
 * 1: soft clamp
 * 2: wrap back
 * 3: allow hdr results
 */
const int overflow = 3;
// transform
const float rotation = 0.; // in Periode
uniform vec2 scale;
uniform vec2 offsetTurbulence;
//复杂度
uniform float complexity;

// sub settings
//子影响
const float subInfluence = 0.5;
//子缩放
const float subScaling = 0.57;
//子旋转
const float subRotation = 0.; // in Periode
//子位移
const vec2 subOffset = vec2(0., 0.);
//中心辅助比例
const bool centerSubscale = false;
//演化
uniform float evolution; // in Periode
//是否循环演化
const bool cycleRevolution = false;
//旋转次数
const int cycle = 1; // not used if cycleRevolution is false
//随机植入
const int randomSeed = 0;


#define PI acos(-1.)
#define TAU 2.*PI

// https://www.shadertoy.com/view/4djSRW
#define HASHSCALE3 vec3(.1031, .1030, .0973)
vec3 hash33(vec3 p3)
{
	p3 = fract(p3 * HASHSCALE3);
    p3 += dot(p3, p3.yxz+19.19);
    return fract((p3.xxy + p3.yxx)*p3.zyx);
}

vec2 flip(vec2 coord) {
    return vec2(-1.0-coord.x, 1.0-coord.y);
}

float bicubic(float a, float b, float c, float d, float t) {
    float p = - a / 2. + b * 3./2. - c * 3./2. + d / 2.;
    float q = a - b * 5./2. + c * 2. - d / 2.;
    float r = - a / 2. + c / 2.;
    float s = b;

    return p * t*t*t + q * t*t + r * t + s;
}

float wrap(float value, float minValue, float maxValue) {
    return mod((value - minValue), (maxValue - minValue)) + minValue;
}

// Fractal Type

float basic(float f) {
    return f;
}
float turbulentBasic(float f) {
    return abs(f - 0.5) * 2.;
}

float turbulentSmooth(float f) {
    float x = turbulentBasic(f);
    return x*x;
}

float turbulentSharp(float f) {
    float x = turbulentBasic(f);
    return sqrt(x);
}
float selectFractal(float f) {
    float ret = 0.;
    if (fractalType == 0) {
        ret = basic(f);
    } else if (fractalType == 1) {
        ret = turbulentSmooth(f);
    } else if (fractalType == 2) {
        ret = turbulentBasic(f);
    } else if (fractalType == 3) {
        ret = turbulentSharp(f);
    } else {
        ret = basic(f);
    }
    return ret;
}

// Cycle

float selectCycle(float value, float base, float periode) {
    float ret = 0.;
    if (cycleRevolution) {
        ret = wrap(value, base, base + periode);
    } else {
        ret = value;
    }
    return ret;
}
// Noise Type

float block(vec2 fragCoord, float depth) {
    float randf = float(randomSeed);
    if (centerSubscale) randf += depth;
    vec3 hash = hash33(vec3(floor(fragCoord), randf));
    float freq = hash.x; // random freq for each coord
    float periode = 1. + floor(freq * float(cycle + 1));
    if (cycleRevolution) {
        freq = periode / float(cycle);
    }
    float evo = evolution * freq + hash.y;
    float e = randf + floor(evo); // evolution here
    float f = fract(evo);

    float a = hash33(vec3(floor(fragCoord), selectCycle(e - 1., randf, periode))).x;
    float b = hash33(vec3(floor(fragCoord), selectCycle(e + 0., randf, periode))).x;
    float c = hash33(vec3(floor(fragCoord), selectCycle(e + 1., randf, periode))).x;
    float d = hash33(vec3(floor(fragCoord), selectCycle(e + 2., randf, periode))).x;

    return bicubic(a, b, c, d, f);
}

float linear(vec2 fragCoord, float depth) {
    fragCoord -= 0.5;
    float tl = block(fragCoord, depth);
    float tr = block(fragCoord + vec2(1., 0.), depth);
    float bl = block(fragCoord + vec2(0., 1.), depth);
    float br = block(fragCoord + vec2(1., 1.), depth);

    vec2 f = fract(fragCoord);
    return mix(mix(tl, tr, f.x), mix(bl, br, f.x), f.y);
}

float softLinear(vec2 fragCoord, float depth) {
    fragCoord -= 0.5;
    float tl = block(fragCoord, depth);
    float tr = block(fragCoord + vec2(1., 0.), depth);
    float bl = block(fragCoord + vec2(0., 1.), depth);
    float br = block(fragCoord + vec2(1., 1.), depth);

    vec2 f = fract(fragCoord);
    f = smoothstep(0., 1., f);
    return mix(mix(tl, tr, f.x), mix(bl, br, f.x), f.y);
}
float spline(vec2 fragCoord, float depth) {
    fragCoord -= 0.5;

    float ttll = block(fragCoord + vec2(-1., -1.), depth);
    float ttl = block(fragCoord + vec2(0., -1.), depth);
    float ttr = block(fragCoord + vec2(1., -1.), depth);
    float ttrr = block(fragCoord + vec2(2., -1.), depth);

    float tll = block(fragCoord + vec2(-1, 0.), depth);
    float tl = block(fragCoord, depth);
    float tr = block(fragCoord + vec2(1., 0.), depth);
    float trr = block(fragCoord + vec2(2, 0.), depth);

    float bll = block(fragCoord + vec2(-1., 1.), depth);
    float bl = block(fragCoord + vec2(0., 1.), depth);
    float br = block(fragCoord + vec2(1., 1.), depth);
    float brr = block(fragCoord + vec2(2., 1.), depth);

    float bbll = block(fragCoord + vec2(-1., 2.), depth);
    float bbl = block(fragCoord + vec2(0., 2.), depth);
    float bbr = block(fragCoord + vec2(1., 2.), depth);
    float bbrr = block(fragCoord + vec2(2., 2.), depth);

    vec2 f = fract(fragCoord);

    float tt = bicubic(ttll, ttl, ttr, ttrr, f.x);
    float t = bicubic(tll, tl, tr, trr, f.x);
    float b = bicubic(bll, bl, br, brr, f.x);
    float bb = bicubic(bbll, bbl, bbr, bbrr, f.x);

    return bicubic(tt, t, b, bb, f.y);
}

// Overflow

float clipOverflow(float value) {
    return clamp(value, 0., 1.);
}
float softClampOverflow(float value) {
    return 1. / (1. + exp(2. - 4.*value));
}

float wrapBackOverflow(float value) {
    return abs(value - 2.*floor(value*0.5 + 0.5));
}

float allowHdrResultsOverflow(float value) {
    return value;
}

float selectOverflow(float value) {
    float ret = 0.;
    if (overflow == 0) {
        ret = clipOverflow(value);
    } else if (overflow == 1) {
        ret = softClampOverflow(value);
    } else if (overflow == 2) {
        ret = wrapBackOverflow(value);
    } else if (overflow == 3) {
        ret = allowHdrResultsOverflow(value);
    } else {
        ret = allowHdrResultsOverflow(value);
    }
    return ret;
}

float layer(vec2 fragCoord, float depth) {
    float ret = 0.;
    if (noiseType == 0) {
        ret = block(fragCoord, depth);
    } else if (noiseType == 1) {
        ret = linear(fragCoord, depth);
    } else if (noiseType == 2) {
        ret = softLinear(fragCoord, depth);
    } else if (noiseType == 3) {
        ret = spline(fragCoord, depth);
    } else {
        ret = spline(fragCoord, depth);
    }
    return selectFractal(ret);
}
mat3 transpose(mat3 A){
    mat3 res;
    for(int i = 0; i < 3; ++i){
       for(int j = 0; j < 3; ++j){
          res[j][i] = A[i][j];
       }
    }
    return res;
}
mat3 inverseMatrix(vec2 translate, float rotate, vec2 scale) {
    return transpose(mat3(
        cos(-rotate)/scale.x, -sin(-rotate)/scale.x, -translate.x,
        sin(-rotate)/scale.y, cos(-rotate)/scale.y, -translate.y,
        0., 0., 1.
    ));
}

vec4 transformed(vec2 fragCoord) {
    mat3 matrix = inverseMatrix(subOffset, subRotation * TAU, vec2(subScaling));

    float val = 0.;

    float totalWeight = 0.;
    mat3 trans = mat3(1.);
    float weight = 1.;
    for (float i=1.; i<complexity; i++) {
        vec2 newCoord = (trans * vec3(fragCoord, 1.)).xy;
        val  += layer(newCoord, i) * weight;

        totalWeight += weight;

        trans = matrix * trans;
        weight *= subInfluence;
    }

    float f = fract(complexity);
    if (f == 0.) f = 1.;

    vec2 newCoord = (trans * vec3(fragCoord, 1.)).xy;
    val  += layer(newCoord, floor(complexity)+1.) * weight * f;

    totalWeight += weight * f;

    val /= totalWeight;

    // color

    if (invert) {
        val = 1. - val;
    }
    val = (val - 0.5) * contrast + 0.5;
    val += brightness;

    val = selectOverflow(val);

    return vec4(vec3(val),1.);
}
void main() {
    vec2 flipCoord = flip(textureCoord);
    mat3 trans = inverseMatrix(offsetTurbulence, rotation * TAU, scale);
    flipCoord = (trans * vec3(flipCoord, 1.)).xy;
    gl_FragColor = transformed(flipCoord);
}
]]

FractalNoise = {}

function FractalNoise:matchWithId(effectId)
    return 'KFM KSkr FractalNoise' == effectId
end

function FractalNoise.createWithId(effectId)
    if not FractalNoise:matchWithId(effectId) then
        return nil
    end
    local o = {
        program = {},
        vertexBuffer = 0
    }
    o = newObject(o, FractalNoise)
    o:init()
    return o
end

function FractalNoise:init()
    local buffer = {}
    glGenBuffers(1, buffer)
    self.vertexBuffer = buffer[1]

    local vertexBufferData = CGE.FloatBuffer:alloc(8)
    vertexBufferData:put(8, { -1, -1, 1, -1, -1, 1, 1, 1}, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, 8, vertexBufferData, GL_STATIC_DRAW)

    self.program = CGE.ProgramObject()
    self.program:bindAttribLocation("position", 0)
    self.program:initWithShaderStrings(vs, fs)
    self.program:bind()

    self.program:sendUniformi("fractalType",1)
    self.program:sendUniformi("noiseType",2)
    self.program:sendUniformf("contrast",1.0)
    self.program:sendUniformf("brightness",0.0)
    self.program:sendUniformf("evolution",0.0)
    self.scaleUnify = true
    self.scaleX = 0.1
    self.scaleY = 0.1
    self.program:sendUniformf("scale",self.scaleX, self.scaleY)
    self.program:sendUniformf("offsetTurbulence",0.0, 0.0)
    self.program:sendUniformf("complexity",6.0)
    --self.program:sendUniformf("center",0.5,0.5)
end

function FractalNoise:onDestroy()
    glDeleteBuffers(1, { self.vertexBuffer })
end

function FractalNoise:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDInt
    elseif index == 2 then
        return FM.AEValueType_OneDInt
    elseif index == 3 then
        return FM.AEValueType_OneDFloat
    elseif index == 4 then
        return FM.AEValueType_OneDFloat
    elseif index == 5 then
        return FM.AEValueType_OneDFloat
    elseif index == 6 then
        return FM.AEValueType_OneDInt
    elseif index == 7 then
        return FM.AEValueType_OneDFloat
    elseif index == 8 then
        return FM.AEValueType_OneDFloat
    elseif index == 9 then
        return FM.AEValueType_OneDFloat
    elseif index == 10 then
        return FM.AEValueType_TwoD
    elseif index == 11 then
        return FM.AEValueType_OneDFloat
    --elseif index == 12 then
    --    return FM.AEValueType_TwoD
    end
    return FM.AEValueType_No_Value
end

function FractalNoise:updateValue(index, value1, value2, value3)
    self.program:bind();
    if index == 1 then
        self.program:sendUniformi("fractalType",value1-1)
    elseif index == 2 then
        self.program:sendUniformi("noiseType",value1-1)
    elseif index == 3 then
        self.program:sendUniformf("contrast", value1);
    elseif index == 4 then
        self.program:sendUniformf("brightness",value1)
    elseif index == 5 then
        self.program:sendUniformf("evolution",value1)
    elseif index == 6 then
        self.scaleUnify = (value1 == 1)
    elseif index == 7 then
        if self.scaleUnify then
            self.scaleX = 0.1+value1/100
            self.scaleY = 0.1+value1/100
            self.program:sendUniformf("scale", self.scaleX, self.scaleY)
        end
    elseif index == 8 then
        if not self.scaleUnify then
            self.scaleX = 0.1+value1/100
            self.program:sendUniformf("scale", self.scaleX, self.scaleY)
        end
    elseif index == 9 then
        if not self.scaleUnify then
            self.scaleY = 0.1+value1/100
            self.program:sendUniformf("scale", self.scaleX, self.scaleY)
        end
    elseif index == 10 then
        self.program:sendUniformf("offsetTurbulence",value1,value2)
    elseif index == 11 then
        self.program:sendUniformf("complexity",value1)
    --elseif index == 12 then
    --    self.program:sendUniformf("center",value1,value2)
    end
end

function FractalNoise:resize(width, height)
    --self.program:bind();
    --self.program:sendUniformf("_mainTexSize", width, height);
end

function FractalNoise:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)

    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)

    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)

    self.program:bind();
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
end
