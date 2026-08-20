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
