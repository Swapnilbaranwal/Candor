#!/bin/bash
# Downloads Candor's 3D illustrations (IconScout, free licence, no attribution required)
# into Assets.xcassets. Run once: double-click in Finder, or `sh Get3DArt.command` in Terminal.
# The links are signed and expire a few days after they were issued; ask Claude for fresh ones if they fail.
cd "$(dirname "$0")/Candor/Assets.xcassets" || exit 1
get() {
  name="$1"; url="$2"
  mkdir -p "$name.imageset"
  if curl -fsSL -o "$name.imageset/$name.png" "$url"; then
    cat > "$name.imageset/Contents.json" <<JSON
{
  "images" : [ { "filename" : "$name.png", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
    echo "✓ $name"
  else
    rm -rf "$name.imageset"; echo "✗ $name (link expired?)"
  fi
}
get IndiaGate3D 'https://download.services.iconscout.com/download?name=delhi-gate&download=1&url=https%3A%2F%2Fdl52s1f61ry7i.cloudfront.net%2F3d%2Ffree%2Foriginal%2F3317716.png%3Ftoken%3DeyJhbGciOiJoczI1NiIsImtpZCI6ImRlZmF1bHQifQ__.eyJpc3MiOiJkbDUyczFmNjFyeTdpLmNsb3VkZnJvbnQubmV0IiwiZXhwIjoxNzkyMTc4NTM0LCJxIjpudWxsLCJpYXQiOjE3OTE5MTkzMzR9.2558d7d9a90f3af07f4d1671f7adf15e873c23b2bf96a58bd62dcd372380be05&width=1000&height=1000'
get HomePin3D 'https://download.services.iconscout.com/download?name=house-location&download=1&url=https%3A%2F%2Fdl52s1f61ry7i.cloudfront.net%2F3d%2Ffree%2Foriginal%2F5665178.png%3Ftoken%3DeyJhbGciOiJoczI1NiIsImtpZCI6ImRlZmF1bHQifQ__.eyJpc3MiOiJkbDUyczFmNjFyeTdpLmNsb3VkZnJvbnQubmV0IiwiZXhwIjoxNzkyMTc4NTM1LCJxIjpudWxsLCJpYXQiOjE3OTE5MTkzMzV9.dbcaf2e24eb51df584e26976548671e24447ab95cd022ee7ec7569c3637821a3&width=1000&height=1000'
get Suitcase3D 'https://download.services.iconscout.com/download?name=business-case&download=1&url=https%3A%2F%2Fdl52s1f61ry7i.cloudfront.net%2F3d%2Ffree%2Foriginal%2F3317711.png%3Ftoken%3DeyJhbGciOiJoczI1NiIsImtpZCI6ImRlZmF1bHQifQ__.eyJpc3MiOiJkbDUyczFmNjFyeTdpLmNsb3VkZnJvbnQubmV0IiwiZXhwIjoxNzkyMTc4NTM2LCJxIjpudWxsLCJpYXQiOjE3OTE5MTkzMzZ9.870b51a062d61067f5439530901481afb0965fd11b9c7503880d127a02efeecb&width=1000&height=1000'
get Adventure3D 'https://download.services.iconscout.com/download?name=adventure&download=1&url=https%3A%2F%2Fdl52s1f61ry7i.cloudfront.net%2F3d%2Ffree%2Foriginal%2F3317709.png%3Ftoken%3DeyJhbGciOiJoczI1NiIsImtpZCI6ImRlZmF1bHQifQ__.eyJpc3MiOiJkbDUyczFmNjFyeTdpLmNsb3VkZnJvbnQubmV0IiwiZXhwIjoxNzkyMTc4NTM2LCJxIjpudWxsLCJpYXQiOjE3OTE5MTkzMzZ9.8c6bb83d545fcf250186ffdf9c4d0fdcf4146b5447628143d9189d9a05fb34a1&width=1000&height=1000'
get Translator3D 'https://download.services.iconscout.com/download?name=language-translator&download=1&url=https%3A%2F%2Fdl52s1f61ry7i.cloudfront.net%2F3d%2Ffree%2Foriginal%2F3317710.png%3Ftoken%3DeyJhbGciOiJoczI1NiIsImtpZCI6ImRlZmF1bHQifQ__.eyJpc3MiOiJkbDUyczFmNjFyeTdpLmNsb3VkZnJvbnQubmV0IiwiZXhwIjoxNzkyMTc4NTM3LCJxIjpudWxsLCJpYXQiOjE3OTE5MTkzMzd9.b69748d7b6c4a27c9e9e23f6d1691e8d44a4892ce7ff25947662ce88804967f0&width=1000&height=1000'
get Train3D 'https://download.services.iconscout.com/download?name=train&download=1&url=https%3A%2F%2Fdl52s1f61ry7i.cloudfront.net%2F3d%2Ffree%2Foriginal%2F3317714.png%3Ftoken%3DeyJhbGciOiJoczI1NiIsImtpZCI6ImRlZmF1bHQifQ__.eyJpc3MiOiJkbDUyczFmNjFyeTdpLmNsb3VkZnJvbnQubmV0IiwiZXhwIjoxNzkyMTc4NTM3LCJxIjpudWxsLCJpYXQiOjE3OTE5MTkzMzd9.4f3f4e3bc06de072ad1755f4162fa9e2678a2c04943bc320638c36334f4204e8&width=1000&height=1000'
get Pin3D 'https://download.services.iconscout.com/download?name=location&download=1&url=https%3A%2F%2Fdl52s1f61ry7i.cloudfront.net%2F3d%2Ffree%2Foriginal%2F2969405.png%3Ftoken%3DeyJhbGciOiJoczI1NiIsImtpZCI6ImRlZmF1bHQifQ__.eyJpc3MiOiJkbDUyczFmNjFyeTdpLmNsb3VkZnJvbnQubmV0IiwiZXhwIjoxNzkyMTc4NTM4LCJxIjpudWxsLCJpYXQiOjE3OTE5MTkzMzh9.f0acc7c6101ca5e1f7a7a6d870fc0a75c2f898887b3ac1dd4e47afa486a13cdc&width=1000&height=1000'
get Camera3D 'https://download.services.iconscout.com/download?name=camera&download=1&url=https%3A%2F%2Fdl52s1f61ry7i.cloudfront.net%2F3d%2Fpremium%2Foriginal%2F4946645.png%3Ftoken%3DeyJhbGciOiJoczI1NiIsImtpZCI6ImRlZmF1bHQifQ__.eyJpc3MiOiJkbDUyczFmNjFyeTdpLmNsb3VkZnJvbnQubmV0IiwiZXhwIjoxNzkyMTc4NTM5LCJxIjpudWxsLCJpYXQiOjE3OTE5MTkzMzl9.967a677d8057b3f77b4e26d1e00b17a1ce3a83ac5f4ec347cb748e2f37118f52&width=1000&height=1000'
echo "Done. Build and run in Xcode."
