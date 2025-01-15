#define CLOUD_MAX_H 194.0
#define CLOUD_MIN_H 164.0
#define CLOUD_WIDTH 1024.0
#define CLOUD_COLOR_BASE vec3(0.5)

// 计算 pos 点的云密度
float cloudDensity(sampler2D noisetex, vec3 pos) {
    pos.x += float(worldTime) / 20;   // add movement

    // 高度衰减
    float mid = (CLOUD_MIN_H + CLOUD_MAX_H) / 2.0;
    float h = CLOUD_MAX_H - CLOUD_MIN_H;
    float weight = 1.0 - 2.0 * abs(mid - pos.y) / h;    // 高度越靠近中间，weight越高
    weight = pow(weight, 0.5);  // smooth
    //weight *= texture2D(noisetex, vec2(pos.y, pos.y*1.34)).x * 0.4 + 0.8;

    // 采样噪声图
    vec2 coord = pos.xz * 0.00125;  // 缩小坐标，增加细节
    float noise = texture2D(noisetex, coord).x;
	noise += texture2D(noisetex, coord * 3.5).x / 3.5;  // 叠加不同频率的噪声
	noise += texture2D(noisetex, coord * 12.25).x / 12.25;
	noise += texture2D(noisetex, coord * 42.87).x / 42.87;	
	noise /= 1.4472;    // normalize, 1+1/3.5+1/12.25+1/42.87=1.4472
    noise *= weight;

    // 截断，消除稀薄部分
    if(noise < 0.45) {
        noise = 0;
    }

    return noise;
}

// get luminance
float lum(vec3 c) {
    return dot(c, vec3(0.2, 0.7, 0.1));
}

vec4 volumeCloud(vec3 worldPos, vec3 cameraPos, vec3 sunPos, sampler2D noisetex, vec3 sunColor) {

    vec4 sum = vec4(0);
    vec3 direction = normalize(worldPos - cameraPos);
    vec3 point = cameraPos;

    // 采样范围加上 CameraPos 偏移到以相机为远点的世界坐标
    float XMAX = cameraPosition.x + CLOUD_WIDTH;
    float XMIN = cameraPosition.x - CLOUD_WIDTH;
    float ZMAX = cameraPosition.z + CLOUD_WIDTH;
    float ZMIN = cameraPosition.z - CLOUD_WIDTH;

    // 如果相机在云层下，将测试起始点移动到云层底部
    if(point.y < CLOUD_MIN_H) {
        point += direction * (abs(CLOUD_MIN_H - cameraPos.y) / abs(direction.y));
    }
    // 如果相机在云层上，将测试起始点移动到云层顶部
    if(CLOUD_MAX_H < point.y) {
        point += direction * (abs(cameraPos.y - CLOUD_MAX_H) / abs(direction.y));
    }
    // 如果像素深度超过到云层距离则放弃采样
    if(length(worldPos - cameraPos) < 0.01 + length(point - cameraPos)) {
        return vec4(0);
    }

    for(int i = 0; i < 50; i++) {        
        float rd = texture2D(noisetex, point.xz).r * 0.2 + 0.9; // 随机步长
        //rd = 1;
        if(i < 25) {  // 前 25 次采样小步长+随机步长            
            point += direction * rd;
        } else {    // 长步长
            point += direction * (1 + float(i - 25) / 5.0) * rd;
        }

        // 超出采样范围则退出
        if(point.y < CLOUD_MIN_H || CLOUD_MAX_H < point.y 
        || XMIN > point.x || point.x > XMAX 
        || ZMIN > point.z || point.z > ZMAX) break;

        // 如果 raymarching hit 到物体则退出
        float pixellen = length(worldPos - cameraPos);
        float samplelen = length(point - cameraPos);
        if(samplelen > pixellen) break;

        // 采样噪声获取密度
        float density = cloudDensity(noisetex, point);

        // 向着光源进行一次采样
        vec3 L = normalize(sunPos - point);
        float density_L = cloudDensity(noisetex, point + L);
        float delta_d = clamp(density - density_L, 0, 1);
        vec3 color_L = vec3(lum(skyColor)) + sunColor * 1.4 * delta_d;
        vec4 color = vec4(color_L * density, density);
        sum += color * (1.0 - sum.a);
    }

    return sum;
}
