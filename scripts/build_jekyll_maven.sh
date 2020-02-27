# This script contains the end-to-end steps for building the website with Jekyll and using Maven to package
# Exit immediately if a simple command exits with a non-zero status.
set -e

JEKYLL_BUILD_FLAGS=""

./scripts/build_gem_dependencies.sh

echo "Ruby version:"
echo `ruby -v`

echo "npm version:"
echo `npm -v`

# Install Antora on the machine
npm i -g @antora/cli@2.1 @antora/site-generator-default@2.1

# Install the Antora site generator package
npm i @antora/site-generator-default@2.1

# Guides that are ready to be published to openliberty.io
echo "Cloning repositories with name starting with guide or iguide..."
ruby ./scripts/build_clone_guides.rb

# Development environment only actions
if [ "$JEKYLL_ENV" != "production" ]; then 
    echo "Not in production environment..."
    echo "Adding robots.txt"
    cp robots.txt src/main/content/robots.txt

    # Development environments with draft docs/guides
    if [ "$JEKYLL_DRAFT_GUIDES" == "true" ]; then
        echo "Clone draft guides for test environments..."
        ruby ./scripts/build_clone_guides.rb "draft-guide"    

        # Need to make sure there are draft-iguide* folders before using the find command
        # If we don't, the find command will fail because the path does not exist
        if [ $(find src/main/content/guides -type d -name "draft-iguide*" | wc -l ) != "0" ] ; then
            echo "Moving any js and css files from draft interactive guides..."
            find src/main/content/guides/draft-iguide* -d -name js -exec cp -R '{}' src/main/content/_assets \;
            find src/main/content/guides/draft-iguide* -d -name css -exec cp -R '{}' src/main/content/_assets \;
        fi
    fi
fi

# Clone docs repo
./scripts/build_clone_docs.sh "modules"

# Development environments that enable the draft blogs in the _draft directory.
if [ "$JEKYLL_DRAFT_BLOGS" == "true" ]; then
    # Include draft blog posts for non production environments
    JEKYLL_BUILD_FLAGS="--drafts"
fi

echo "Copying guide images to /img/guide"
mkdir -p src/main/content/img/guide

# Check if any draft guide images exist.
if ls src/main/content/guides/draft-guide*/assets/* 1> /dev/null 2>&1; then
    echo "Copying draft guide images to /img/guide"
    cp src/main/content/guides/draft-guide*/assets/* src/main/content/img/guide/
fi
# Check if any published guide images exist.
if ls src/main/content/guides/guide*/assets/* 1> /dev/null 2>&1; then
    echo "Copying published guide images to /img/guide"
    cp src/main/content/guides/guide*/assets/* src/main/content/img/guide/
fi

# Move any js/css files from guides to the _assets folder for jekyll-assets minification.
echo "Moving any js and css files published interactive guides..."
# Assumption: There is _always_ iguide* folders
find src/main/content/guides/iguide* -d -name js -exec cp -R '{}' src/main/content/_assets \;
find src/main/content/guides/iguide* -d -name css -exec cp -R '{}' src/main/content/_assets \;

# Build draft and published blogs
./scripts/build_clone_blogs.sh

# Jekyll build
echo "Building with jekyll..."
echo `jekyll -version`
mkdir -p target/jekyll-webapp

# Enable google analytics if ga is true
if [ "$ga" = true ]
  then 
    jekyll build $JEKYLL_BUILD_FLAGS --source src/main/content --config src/main/content/_config.yml,src/main/content/_google_analytics.yml --destination target/jekyll-webapp 
  else
    jekyll build $JEKYLL_BUILD_FLAGS --source src/main/content --destination target/jekyll-webapp 
fi

# Install Antora packages and build the Antora UI bundle
./scripts/build_antora_ui.sh

# Use the Antora playbook to download the docs and build the doc pages
./scripts/build_clone_antora_playbook.sh

echo "Using the Antora playbook to generate what content to display for docs"
antora --fetch --stacktrace src/main/content/docs/antora-playbook.yml

# Copy the contents generated by Antora to the website folder
echo "Moving the Antora docs to the jekyll webapp"
mkdir -p target/jekyll-webapp/docs/ref/
cp -r src/main/content/docs/build/site/. target/jekyll-webapp/docs/ref/

# python3 ./scripts/parse-feature-toc.py

# Maven packaging
echo "Running maven (mvn)..."
mvn -B package
