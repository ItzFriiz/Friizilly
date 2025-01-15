#define SHADOW_SOFTNESS 2
#define SHADOW_QUALITY 1
const int shadowMapResolution = 4096;

vec2 distort(vec2 shadowTexturePosition) { // distort shadow texture to simulate depth of field, make shadows closer to the player more detailed
    float distanceFromPlayer = length(shadowTexturePosition);
    vec2 distortedPosition = shadowTexturePosition / mix(1.0,distanceFromPlayer,0.9);
    return distortedPosition;
}