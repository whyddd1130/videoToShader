
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
varying vec2 uv0;

uniform sampler2D inputImageTexture;
#define amount (0.2 + 3.0 * uProgress)
#define range 1.0
#define passthrough 0.0
#define width vec2(1.0, 1.0)
#define imageHeight 1080
#define imageWidth 1080
#define intensity (0.2 + 2.5 * uProgress)
vec4 edges()
{
    vec2 vUv=uv0;
    vec2 texel= width / vec2(imageWidth,imageHeight);
    mat3 G[2];
    const mat3 g0=mat3(1.,2.,1.,0.,0.,0.,-1.,-2.,-1.);
    const mat3 g1=mat3(1.,0.,-1.,2.,0.,-2.,1.,0.,-1.);

    mat3 I;
    float cnv[2];
    vec3 sample;
    G[0]=g0;
    G[1]=g1;
    for(float i=0.;i<3.;i++){
        for(float j=0.;j<3.;j++){
            sample=texture2D(inputImageTexture,vUv+texel*vec2(i-1.,j-1.)).rgb;
            I[int(i)][int(j)]=length(sample);
        }
    }
    for(int i=0;i<2;i++){
        float dp3=dot(G[i][0],I[0])+dot(G[i][1],I[1])+dot(G[i][2],I[2]);
        cnv[i]=dp3*dp3;
    }
    vec4 orig=texture2D(inputImageTexture,vUv);
    vec4 resultColor=orig*passthrough+vec4(.5*sqrt(cnv[0]*cnv[0]+cnv[1]*cnv[1]))*amount;
    resultColor.rgb *= (intensity + 0.01);
    resultColor.a = 1.0;
    return resultColor;
}


void main(void)
{
    vec4 resultColor=edges();

    resultColor.a = 1.0;
    gl_FragColor=resultColor;
}

]]

ShaderLabf0fce3b77667 = {}

function ShaderLabf0fce3b77667:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLabf0fce3b77667' == effectId
end

function ShaderLabf0fce3b77667.createWithId(effectId)
    if not ShaderLabf0fce3b77667:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLabf0fce3b77667)
    o:init()
    return o
end

function ShaderLabf0fce3b77667:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLabf0fce3b77667:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLabf0fce3b77667:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLabf0fce3b77667:resize(width, height)
end

function ShaderLabf0fce3b77667:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLabf0fce3b77667:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLabf0fce3b77667:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLabf0fce3b77667:onDestroy()
end
