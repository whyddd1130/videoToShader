
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
#define iTime uTime
#define rIns (0.3 + 2.0 * uProgress)
#define gIns (0.3 + 2.0 * uProgress)
#define bIns (0.3 + 2.0 * uProgress)
varying vec2 uv;
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
// vec4 hash24(vec2 p){
//     vec4 p4 = fract(p.xyxy*34.5);
//     p4+=dot(p4,p4.wyzx+(15.44));
//     return fract((p4+p4.wyzx)*p4.yzxw);
// }
vec3 hash23(vec2 p){
    vec3 p3 = fract(p.xyx*33.5);
    p3+=dot(p3,p3.yzx+(12.1+iTime));
    return fract((p3.xyz+p3.yzx)*p3.zyx);
}
vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
vec3 blendColor(vec3 base, vec3 blend) {
    float topgray = dot(blend.rgb,vec3(0.299,0.587, 0.114));
    float bottomgray = dot(base.rgb,vec3(0.299,0.587, 0.114));
    vec3 resultCol = blend.rgb - topgray+bottomgray;
    //  if(resultCol.r>1.||resultCol.g>1.||resultCol.b>1.){
    //         resultCol = vec3(1.)*(bottomgray-topgray)/(1.-topgray)+blend.rgb;
    //     }
    return resultCol;
}
float blendDarken(float base, float blend) {
    return min(blend,base);
}

vec3 blendDarken(vec3 base, vec3 blend) {
    return vec3(blendDarken(base.r,blend.r),blendDarken(base.g,blend.g),blendDarken(base.b,blend.b));
}
void main()
{
    float scale = 2.0;
    // vec3 oriCol = texture2D(inputImageTexture,uv).rgb;
    // float gray = dot(oriCol.rgb,vec3(0.299 ,0.587,0.114));
    // vec2 noiseUV = floor(uv*(u_ScreenParams.xy)/scale)/u_ScreenParams.xy*scale;
    vec2 noiseUV = uv;
    vec3 firstNoise  = hash23(noiseUV);
    vec3 resultNoise = firstNoise;
    resultNoise=(resultNoise-vec3(0.5))*vec3(rIns,gIns,bIns)+vec3(0.5);
    gl_FragColor = vec4(firstNoise,1.0);
}

]]

ShaderLabd742f7f00c30 = {}

function ShaderLabd742f7f00c30:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLabd742f7f00c30' == effectId
end

function ShaderLabd742f7f00c30.createWithId(effectId)
    if not ShaderLabd742f7f00c30:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLabd742f7f00c30)
    o:init()
    return o
end

function ShaderLabd742f7f00c30:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLabd742f7f00c30:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLabd742f7f00c30:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLabd742f7f00c30:resize(width, height)
end

function ShaderLabd742f7f00c30:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLabd742f7f00c30:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLabd742f7f00c30:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLabd742f7f00c30:onDestroy()
end
