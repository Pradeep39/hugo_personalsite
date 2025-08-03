#hugo mod init github.com/Pradeep39/hugo_personalsite
# download the theme
hugo mod get -u
# download the theme's dependencies
hugo mod tidy
# generate node dependencies
hugo mod npm pack
# install install dependencies
npm install
hugo server -w > /dev/null 2>1 &
PID=$!
sleep 15
kill -9 $PID
find ./public -type f -name "*.html" -print0 | xargs -0 sed -i '' -e 's/public"/public\/index.html"/g'
find ./public -type f -name "*.html" -print0 | xargs -0 sed -i '' -e 's/public#/public\/index.html#/g'
find ./public -type f -name "*.html" -print0 | xargs -0 sed -i '' -e 's/public\/#/public\/index.html#/g'
find ./public -type f -name "*.html" -print0 | xargs -0 sed -i '' -e 's/public\/posts"/public\/posts.html"/g'
find ./public -type f -name "*.html" -print0 | xargs -0 sed -i '' -e 's/"\/posts\/"/"\/mysite\/public\/posts.html"/g'
find ./public -type f -name "*.html" -print0 | xargs -0 sed -i '' -e 's/"\/posts"/"\/mysite\/public\/posts.html"/g'
find ./public -type f -name "*.html" -print0 | xargs -0 sed -i '' -e 's/public\/search"/public\/search.html"/g'
find ./public -type f -name "*.html" -print0 | xargs -0 sed -i '' -e 's/public\/tags"/public\/tags.html"/g'
find ./public -type f -name "*.html" -print0 | xargs -0 sed -i '' -e 's/http:\/\/localhost:1313\//\//g'