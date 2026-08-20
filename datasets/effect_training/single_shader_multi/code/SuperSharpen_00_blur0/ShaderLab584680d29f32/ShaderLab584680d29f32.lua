
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
uniform sampler2D inputImageTexture;
varying vec2 uv;
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
#define blurSize (1.0 + 34.0 * uProgress)
void main()
{
    vec2 mySize = u_ScreenParams.xy/min(u_ScreenParams.x,u_ScreenParams.y)*720.;
    vec2 offset = vec2(0.0,1.)*vec2(blurSize)/mySize;

    float half_gaussian_weight[9];
    
    half_gaussian_weight[0]= 0.30;
    half_gaussian_weight[1]= 0.25;
    half_gaussian_weight[2]= 0.2;
    half_gaussian_weight[3]= 0.18;
    half_gaussian_weight[4]= 0.16;
    half_gaussian_weight[5]= 0.15;
    half_gaussian_weight[6]= 0.1;
    half_gaussian_weight[7]= 0.05;
    half_gaussian_weight[8]= 0.02;
    vec4 resultCol = texture2D(inputImageTexture, uv);
    float num = 1.0;
    for(int i = 1 ;i <= 8 ;i++){
        float j = float(i);
        resultCol+= texture2D(inputImageTexture, uv+j*offset);
        resultCol+= texture2D(inputImageTexture, uv-j*offset);
        num+=2.0;
    }
    resultCol/=num;

    gl_FragColor = vec4(resultCol);
}

]]

ShaderLab584680d29f32 = {}

function ShaderLab584680d29f32:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLab584680d29f32' == effectId
end

function ShaderLab584680d29f32.createWithId(effectId)
    if not ShaderLab584680d29f32:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLab584680d29f32)
    o:init()
    return o
end

function ShaderLab584680d29f32:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLab584680d29f32:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLab584680d29f32:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLab584680d29f32:resize(width, height)
end

function ShaderLab584680d29f32:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLab584680d29f32:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLab584680d29f32:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLab584680d29f32:onDestroy()
end
