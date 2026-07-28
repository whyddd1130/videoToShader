
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
#define glithIns (0.2 + 1.2 * uProgress)
#define blurSize (1.0 + 34.0 * uProgress)
void main()
{
    vec2 mySize = u_ScreenParams.xy/min(u_ScreenParams.x,u_ScreenParams.y)*720.;
    vec2 offset = vec2(0.6)/mySize;

    vec2 myuv = vec2(uv.x,uv.y);
    vec4 col = texture2D(inputImageTexture,myuv);
    vec4 oriCol = col;
    col.r = texture2D(inputImageTexture,myuv+glithIns*offset*vec2(2,2)).r;
    col.g = texture2D(inputImageTexture,myuv+glithIns*offset*vec2(2,0)).g;
    col.b = texture2D(inputImageTexture,myuv+glithIns*offset*vec2(-2,0.6)).b;
    // blendColor.r = texture2D(inputImageTexture, uv + vec2(rx / float(imageWidth), ry/float(imageHeight))).r;
    // blendColor.g = texture2D(inputImageTexture, uv + vec2(gx / float(imageWidth), gy/float(imageHeight))).g;
    // blendColor.b = texture2D(inputImageTexture, uv + vec2(bx / float(imageWidth), by/float(imageHeight))).b;
    // col.b = texture2D(inputImageTexture,myuv+offset).b;

    gl_FragColor = vec4(mix(vec3(0.5),(col.rgb-oriCol.rgb)*0.5+0.5,1.0),1.0);
}

]]

ShaderLab85925033f7ab = {}

function ShaderLab85925033f7ab:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLab85925033f7ab' == effectId
end

function ShaderLab85925033f7ab.createWithId(effectId)
    if not ShaderLab85925033f7ab:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLab85925033f7ab)
    o:init()
    return o
end

function ShaderLab85925033f7ab:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLab85925033f7ab:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLab85925033f7ab:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLab85925033f7ab:resize(width, height)
end

function ShaderLab85925033f7ab:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLab85925033f7ab:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLab85925033f7ab:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLab85925033f7ab:onDestroy()
end
