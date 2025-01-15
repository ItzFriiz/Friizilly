#version 460

uniform sampler2D colortex0;
uniform sampler2D colortex1;

uniform float viewHeight;
uniform float viewWidth;

in vec2 texCoord;

/* DRAWBUFFERS:05 */
layout(location = 0) out vec4 outColor0;

void main() {
    vec4 color = texture2D(colortex0, texCoord);
    vec4 cloud = vec4(0);
    float weight = 0.;

    // 体积云虚化
    for(int i = -1; i <= 1; i++) {
        for(int j = -1; j <= 1; j++) {
            vec2 offset = vec2(float(i) / viewWidth, float(j) / viewHeight) * 2.;
            cloud += texture2D(colortex1, texCoord * 0.5 + offset);
            weight += 1;
        }
    }
    cloud /= weight;
    color.rgb = mix(color.rgb, cloud.rgb, clamp(cloud.a, 0, 1));
    outColor0 = color;
}