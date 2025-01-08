#version 460 compatibility

uniform sampler2D lightmap;

layout(location = 0) out vec4 outColor0;

in vec4 blockColor;
in vec2 lightMapCoords;

void main() {
    vec3 lightColor = pow(texture(lightmap, lightMapCoords).rgb, vec3(2.2));
    vec4 outputColorData = blockColor;
    vec3 outputColor = outputColorData.rgb * lightColor;
    float transparency = outputColorData.a;
    if (transparency < .1) {
        discard;
    }
    outColor0 = pow(vec4(outputColor, transparency), vec4(1 / 2.2));
}