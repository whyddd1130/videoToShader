
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
varying vec2 uv0;

uniform sampler2D inputImageTexture;
#define time uTime
#define noiseTexture inputImageTexture
#define filterIntensity (0.2 + 1.0 * uProgress)
#define rangeIntensity (0.10 + 2.40 * uProgress)
#define level 2
#define V vec2(0.0,1.0)
#define PI 3.14159265
#define VHSRES vec2(2560.0,1920.0)
#define saturate(i) clamp(i,0.0,1.0)
#define lofi(i,d) floor(i/d)*d
//#define validuv(v) (abs(v.x-0.5)<0.5&&abs(v.y-0.5)<0.5)

highp float v2random(highp vec2 uv) {
    return texture2D(noiseTexture, mod(uv, vec2(1.0))).x;
}

highp vec3 rgb2yiq(highp vec3 rgb) {
    return mat3(0.299, 0.596, 0.211, 0.587, -0.274, -0.523, 0.114, -0.322, 0.312) * rgb;
}

highp vec3 yiq2rgb(highp vec3 yiq) {
    return mat3(1.000, 1.000, 1.000, 0.956, -0.272, -1.106, 0.621, -0.647, 1.703) * yiq;
}

highp vec3 vhsTex2D(highp vec2 uv) {
    if (abs(uv.x-0.5)<0.5&&abs(uv.y-0.5)<0.5) {
        highp vec3 y = V.yxx * rgb2yiq(texture2D(inputImageTexture, uv).xyz);
        highp vec3 c = V.xyy * rgb2yiq(texture2D(inputImageTexture, uv - 3.0 * V.yx / VHSRES.x).xyz);
        return yiq2rgb(y + c);
    } else {
        return vec3(0.1, 0.1, 0.1);
    }
}

void main() {
    highp float waveFactor = 36.0;
    highp float speedFactor = 1.50;

    // if (level == 0) {

    // } else if (level == 1) {
    //     waveFactor = 6.0;
    //     speedFactor = 2.0;
    // } else {
    //     waveFactor = 15.0;
    //     speedFactor = 0.50;
    // }

    highp vec2 uv = uv0;

    highp float iTime = -time*0.5;

    highp vec2 uvn = uv;
    highp vec3 col = vec3(0.0, 0.0, 0.0);

    // tape wave
    uvn.x += (v2random(vec2(uvn.y / 10.0, iTime / 10.0) / 1.0) - 0.5) / VHSRES.x * waveFactor * rangeIntensity;
    uvn.x += (v2random(vec2(uvn.y, iTime * 10.0)) - 0.5) / VHSRES.x * 2.0;

    // tape crease
    highp float tcPhase = smoothstep(0.9, 0.96, sin(uvn.y * 8.0 - (iTime * speedFactor + 0.14 * v2random(iTime * vec2(0.67, 0.59))) * PI * 1.2));
    highp float tcNoise = smoothstep(0.3, 1.0, v2random(vec2(uvn.y * 4.77, iTime)));
    highp float tc = tcPhase * tcNoise;
    uvn.x = uvn.x - tc / VHSRES.x * 8.0;

    // switching noise
    highp float snPhase = smoothstep(6.0 / VHSRES.y, 0.0, uvn.y);
    uvn.y += snPhase * 0.3;
    uvn.x += snPhase * ((v2random(vec2(uv.y * 100.0, iTime * 10.0)) - 0.5) / VHSRES.x * 24.0);

    // fetch
    col = vhsTex2D(uvn);

    // crease noise
    highp float cn = tcNoise * (0.3 + 0.7 * tcPhase);
    if (0.59 < cn) {
        highp vec2 uvt = (uvn + V.yx * v2random(vec2(uvn.y, iTime))) * vec2(0.1, 1.0);
        highp float n0 = v2random(uvt);
        highp float n1 = v2random(uvt + V.yx / VHSRES.x);
        if (n1 < n0) {
            col = mix(col, 2.0 * V.yyy, pow(n0, 5.0));
        }
    }

    // switching color modification
    col = mix(
        col,
        col.yzx,
        snPhase * 0.4
    );

    // ac beat
    col *= 1.0 + 0.1 * smoothstep(0.4, 0.6, v2random(vec2(0.0, 0.1 * (uv.y + iTime * 0.2)) / 10.0));
    vec3 tempColor = col;
    // color noise
    col *= 0.9 + 0.1 * texture2D(noiseTexture, mod(uvn * vec2(1.0, 1.0) + iTime * vec2(5.97, 4.45), vec2(1.0))).xyz;
    col = saturate(col);
    col = mix(tempColor, col, filterIntensity);
    vec4 resultColor = vec4(col, 1.0);
    resultColor.a = texture2D(inputImageTexture, uv0).a;
    gl_FragColor = resultColor;
}
]]

ShaderLab232f42ed504d = {}

function ShaderLab232f42ed504d:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLab232f42ed504d' == effectId
end

function ShaderLab232f42ed504d.createWithId(effectId)
    if not ShaderLab232f42ed504d:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLab232f42ed504d)
    o:init()
    return o
end

function ShaderLab232f42ed504d:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLab232f42ed504d:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLab232f42ed504d:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLab232f42ed504d:resize(width, height)
end

function ShaderLab232f42ed504d:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLab232f42ed504d:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLab232f42ed504d:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLab232f42ed504d:onDestroy()
end
