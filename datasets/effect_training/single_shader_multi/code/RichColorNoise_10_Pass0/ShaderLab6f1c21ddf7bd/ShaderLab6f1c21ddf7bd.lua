
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
#define inputWidth 1080
#define inputHeight 1080
#define blurSize (1.0 + 34.0 * uProgress)
#define textureCoordinate uv

float setMaskVal(vec4 color,vec3 weight)
{
    if(dot(color.rgb,weight)>0.5)
        return 0.0;             
    else
        return 1.0;
}

void main()
{
    vec2 screenSize = vec2(inputWidth,inputHeight);
    screenSize= screenSize/min(screenSize.x,screenSize.y)*720.;
    const int  radius = 8;
    vec3 W = vec3(0.299,0.587,0.114);

    float half_gaussian_weight[9];
    
    half_gaussian_weight[0]= 0.20;//0.137401;
    half_gaussian_weight[1]= 0.19;//0.125794;
    half_gaussian_weight[2]= 0.17;//0.106483;
    half_gaussian_weight[3]= 0.15;//0.080657;
    half_gaussian_weight[4]= 0.13;//0.054670;
    half_gaussian_weight[5]= 0.11;//0.033159;
    half_gaussian_weight[6]= 0.08;//0.017997;
    half_gaussian_weight[7]= 0.05;//0.008741;
    half_gaussian_weight[8]= 0.02;//0.003799;
    
    
    vec4 sum            = vec4(0.0);
    vec4 result         = vec4(0.0);
    vec2 unit_uv        = vec2(blurSize/screenSize.x,blurSize/screenSize.y)*1.25;
    vec4 curColor       = texture2D(inputImageTexture, textureCoordinate);
    // float alpha = curColor.a;
    // curColor.a = setMaskVal(curColor,W);
    vec4 centerPixel    = curColor*half_gaussian_weight[0];
    
    float sum_weight    = half_gaussian_weight[0];
    //horizontal
    for(int i=1;i<=radius;i++)
    {
        vec2 curRightCoordinate = textureCoordinate+vec2(float(i),0.0)*unit_uv;
        vec2 curLeftCoordinate  = textureCoordinate+vec2(float(-i),0.0)*unit_uv;
        vec4 rightColor = texture2D(inputImageTexture,curRightCoordinate);
        vec4 leftColor = texture2D(inputImageTexture,curLeftCoordinate);
        // rightColor.a = setMaskVal(rightColor,W);
        // leftColor.a = setMaskVal(leftColor,W);
        sum+=rightColor*half_gaussian_weight[i];
        sum+=leftColor*half_gaussian_weight[i];
        sum_weight+=half_gaussian_weight[i]*2.0;
    }
    
    result = (sum+centerPixel)/sum_weight; 
    // result.a = alpha;

    gl_FragColor = result;
}

]]

ShaderLab6f1c21ddf7bd = {}

function ShaderLab6f1c21ddf7bd:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLab6f1c21ddf7bd' == effectId
end

function ShaderLab6f1c21ddf7bd.createWithId(effectId)
    if not ShaderLab6f1c21ddf7bd:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLab6f1c21ddf7bd)
    o:init()
    return o
end

function ShaderLab6f1c21ddf7bd:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLab6f1c21ddf7bd:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLab6f1c21ddf7bd:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLab6f1c21ddf7bd:resize(width, height)
end

function ShaderLab6f1c21ddf7bd:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLab6f1c21ddf7bd:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLab6f1c21ddf7bd:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLab6f1c21ddf7bd:onDestroy()
end
