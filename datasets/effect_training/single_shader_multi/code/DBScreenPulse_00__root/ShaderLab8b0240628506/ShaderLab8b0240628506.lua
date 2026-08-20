
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
varying vec2 textureCoordinate;
varying vec2 uRenderSize;

void main()
{
    vec2 t = position * 0.5 + 0.5;
    uv = t;
    uv0 = t;
    v_uv = t;
    textureCoord = t;
    texCoord = t;
    textureCoordinate = t;
    uRenderSize = vec2(1080.0, 1080.0);
    gl_Position = vec4(position, 0.0, 1.0);
}

]]

local fs = [[
precision highp float;

uniform float uProgress;
uniform float uTime;
varying highp vec2 uv0;
uniform sampler2D inputImageTexture;
#define iTime uTime
#define scope (0.01 + 0.18 * uProgress)
#define speed (0.8 + 3.0 * uProgress)
#define rate (4.0 + 30.0 * uProgress)
#define twistX 1
// #define PI = 3.14159;
// 
void main()
{
 float s = 1.0 - scope * 2.0;

  float ox = uv0.x;
  float oy = uv0.y;

    ox = sin(mod(uv0.y * rate * 2.0, 2.0) * 3.14159) * scope;
    ox = (uv0.x) + ox * sin(iTime);
    if (ox < 0.0){
      ox = -ox;
    }else if(ox > 1.0){
      ox = 2.0 - ox;

  }
//  if(twistY == 1){
//    oy = sin(mod(coordnate.x * rate * 2.0 + time * speed, 2.0) * PI) * scope;
//    oy = coordnate.y * s + scope + oy;
//  }

  vec2 uv = vec2(ox, oy);

  vec4 color = texture2D(inputImageTexture, uv);

  gl_FragColor = color;
}

]]

ShaderLab8b0240628506 = {}

function ShaderLab8b0240628506:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLab8b0240628506' == effectId
end

function ShaderLab8b0240628506.createWithId(effectId)
    if not ShaderLab8b0240628506:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLab8b0240628506)
    o:init()
    return o
end

function ShaderLab8b0240628506:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLab8b0240628506:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLab8b0240628506:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLab8b0240628506:resize(width, height)
end

function ShaderLab8b0240628506:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLab8b0240628506:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLab8b0240628506:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLab8b0240628506:onDestroy()
end
