
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
varying vec2 uv;
varying vec2 uRenderSize;
uniform sampler2D inputImageTexture;
#define timer uTime
#define fRadius (1.0 + 24.0 * uProgress)
#define blurSize (1.0 + 34.0 * uProgress)
#define TWO_PI (3.141592653*2.0)


void main()
{
	float radius = fRadius;
	float weight = 1.0;
//    float time = clamp(timer,0.0,1.0);
    float time = mod(timer,1.0);
	vec2 centerUV = vec2(0.5)*uRenderSize;
    vec2 realUV = uv*uRenderSize;
	//1567568470557692194-37042850737695692125183738914177420858-81863384158177871172227896524115562324405160924254929502
	float zoomCoeff = 1.0;
	//5598084541745239087-67527639150899854295183738914177420858-81863384158177871172227896524115562324405160924254929502
	float blurCoeff = 1.0;
	//-804609470840025752078592422863657563675183738914177420858-81863384158177871172227896524115562324405160924254929502
	float brightnessCoeff = 1.0;

	if(time<0.2)
	{
		zoomCoeff = 0.8+0.1*time/0.2;
		realUV = centerUV+(realUV-centerUV)*zoomCoeff;
	}
	else if(time<0.4)
	{
		zoomCoeff = 0.9;
		realUV = centerUV+(realUV-centerUV)*zoomCoeff;
	}
	else if(time<0.8)
	{
		zoomCoeff = 0.9+0.1*(time-0.4)/0.4;
		realUV = centerUV+(realUV-centerUV)*zoomCoeff;
	}
	
	if(time<=0.92 && time>=0.24)
	{
		float mid = (0.92+0.24)*0.5;
		float range = (0.92-0.24)*0.5;
		blurCoeff = 1.0-abs(time-mid)/range;
		radius *= blurCoeff;
	}
	else
	{
		radius = 0.0;
	}

	if(time>0.4 && time<=1.0)
	{
		float mid = (1.0+0.4)*0.5;
		float range = (1.0-0.4)*0.5;
		brightnessCoeff = 1.0-abs(time-mid)/range;
		brightnessCoeff = 1.0+0.6*brightnessCoeff;
	}

    vec2 direction = realUV - centerUV;
	float coeff = length(direction)/length(centerUV);
    vec2 step = direction/distance(realUV,centerUV)*blurSize*pow(coeff,0.85);

    vec4 curColor = texture2D(inputImageTexture, uv)*weight*brightnessCoeff;
    vec4 sumColor = curColor;
    float sumWeight    = weight;
    //radial blur

	const float MAX_VALUE = 25.;
	vec2 screenSize = vec2(720.0) * uRenderSize.xy / min(uRenderSize.x, uRenderSize.y);
    for(float i=1.0;i<=MAX_VALUE;i+=1.0)
    {
		if (i > radius) break;
        vec2 curStep = step*float(i);
        vec2 curRightCoordinate = (realUV+curStep)/screenSize;//textureCoordinate+curStep;
        vec2 curLeftCoordinate  = (realUV-curStep)/screenSize;//textureCoordinate-curStep;
        vec4 rightColor = texture2D(inputImageTexture,curRightCoordinate)*brightnessCoeff;
        vec4 leftColor = texture2D(inputImageTexture,curLeftCoordinate)*brightnessCoeff;
        sumColor+=rightColor*weight;
        sumColor+=leftColor*weight;
		sumWeight+=weight*2.0;
    }
    vec4 resultColor = sumColor/sumWeight;
	// resultColor.a = texture2D(inputImageTexture, uv).a;
    gl_FragColor = resultColor;
}

]]

ShaderLab8f3680e0a069 = {}

function ShaderLab8f3680e0a069:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLab8f3680e0a069' == effectId
end

function ShaderLab8f3680e0a069.createWithId(effectId)
    if not ShaderLab8f3680e0a069:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLab8f3680e0a069)
    o:init()
    return o
end

function ShaderLab8f3680e0a069:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLab8f3680e0a069:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLab8f3680e0a069:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLab8f3680e0a069:resize(width, height)
end

function ShaderLab8f3680e0a069:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLab8f3680e0a069:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLab8f3680e0a069:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLab8f3680e0a069:onDestroy()
end
