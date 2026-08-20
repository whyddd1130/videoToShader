
local function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end

local vs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

attribute vec2 position;
varying vec2 uv;
varying vec2 uv0;
varying vec2 v_uv;
varying vec2 textureCoord;
varying vec2 texCoord;

void main()
{
    vec2 t = position * 0.5 + 0.5;
    uv = t;
    uv0 = t;
    v_uv = t;
    textureCoord = t;
    texCoord = t;
    gl_Position = vec4(position, 0.0, 1.0);
}

]]

local fs = [[
precision highp float;


uniform float uProgress;
uniform float uTime;
varying vec2 uv;
uniform sampler2D inputImageTexture;
#define u_sample (2.0 + 48.0 * uProgress)
#define textureCoordinate uv
#define u_baseTexWidth 1080.0
#define u_baseTexHeight 1080.0
float normpdf(in float x, in float sigma)
{
    return 0.39894 * exp(-0.5 * x * x / (sigma * sigma)) / sigma;
}

vec4 gaussianBlur(sampler2D i_InputTex, vec2 i_Uv, vec2 i_Dir, vec2 screenSize)
{
    float sigma = 4.0;
    float weight = normpdf(0.0, sigma);

    vec4 sum = vec4(0.0);
    vec4 result = vec4(0.0);
    vec2 unit_uv = i_Dir / screenSize;
    float gamma = 1.0;
    vec4 curColor = texture2D(i_InputTex, i_Uv);
    vec4 centerPixel = pow(curColor, vec4(gamma)) * weight;
    float sum_weight = weight;

    float s = u_sample;
    for (int i = 1; i <= 1024; i++) {
        if (float(i) > u_sample) {
            break;
        }
        vec2 curRightCoordinate = i_Uv + float(i) * unit_uv;
        vec2 curLeftCoordinate = i_Uv + float(-i) * unit_uv;
        // curRightCoordinate = step(u_mirrorEdge, 0.5)*curRightCoordinate + (1.0-step(u_mirrorEdge,
        // 0.5))*Mirror(curRightCoordinate); curLeftCoordinate = step(u_mirrorEdge, 0.5)*curLeftCoordinate +
        // (1.0-step(u_mirrorEdge, 0.5))*Mirror(curLeftCoordinate);
        vec4 rightColor = texture2D(i_InputTex, curRightCoordinate);
        vec4 leftColor = texture2D(i_InputTex, curLeftCoordinate);
        weight = normpdf(float(i) / s * 15.0, sigma);
        sum += pow(rightColor, vec4(gamma)) * weight;
        sum += pow(leftColor, vec4(gamma)) * weight;
        sum_weight += weight * 2.0;
    }

    result = (sum + centerPixel) / sum_weight;
    result = pow(result, vec4(1.0 / gamma));
    return clamp(result, 0.0, 1.0);
}
void main()
{
    vec2 screenSize = vec2(u_baseTexWidth, u_baseTexHeight) / min(u_baseTexWidth, u_baseTexHeight) * 720.;
    vec2 blurDir = vec2(0, 1);
    gl_FragColor = gaussianBlur(inputImageTexture, uv, blurDir, screenSize);
}

]]

ShaderLab27a8ea721c90 = {}

function ShaderLab27a8ea721c90:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLab27a8ea721c90' == effectId
end

function ShaderLab27a8ea721c90.createWithId(effectId)
    if not ShaderLab27a8ea721c90:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLab27a8ea721c90)
    o:init()
    return o
end

function ShaderLab27a8ea721c90:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLab27a8ea721c90:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLab27a8ea721c90:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLab27a8ea721c90:resize(width, height)
end

function ShaderLab27a8ea721c90:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLab27a8ea721c90:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLab27a8ea721c90:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLab27a8ea721c90:onDestroy()
end
