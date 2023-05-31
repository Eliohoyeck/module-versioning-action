#!/bin/bash


set -o pipefail

# config
default_semvar_bump=${DEFAULT_BUMP:-minor}
default_branch=${DEFAULT_BRANCH:-$GITHUB_BASE_REF} # get the default branch from github runner env vars
tag_prefix=${TAG_PREFIX:-}
modules_path=${MODULES_PATH:-}
release_branches=${RELEASE_BRANCHES:-master,main}
custom_tag=${CUSTOM_TAG:-}
source=${SOURCE:-.}
dryrun=${DRY_RUN:-false}
initial_version=${INITIAL_VERSION:-0.0.0}
tag_context=${TAG_CONTEXT:-repo}
prerelease=${PRERELEASE:-false}
suffix=${PRERELEASE_SUFFIX:-beta}
verbose=${VERBOSE:-false}
major_string_token=${MAJOR_STRING_TOKEN:-#major}
minor_string_token=${MINOR_STRING_TOKEN:-#minor}
patch_string_token=${PATCH_STRING_TOKEN:-#patch}
none_string_token=${NONE_STRING_TOKEN:-#none}
branch_history=${BRANCH_HISTORY:-last}
# since https://github.blog/2022-04-12-git-security-vulnerability-announced/ runner uses?
git config --global --add safe.directory /github/workspace


cd "${GITHUB_WORKSPACE}/${source}" || exit 1


echo "*** CONFIGURATION ***"
echo -e "\tDEFAULT_BUMP: ${default_semvar_bump}"
echo -e "\tDEFAULT_BRANCH: ${default_branch}"
echo -e "\tTAG_PREFIX: ${tag_prefix}"
echo -e "\tMODULES_PATH: ${modules_path}"
echo -e "\tRELEASE_BRANCHES: ${release_branches}"
echo -e "\tCUSTOM_TAG: ${custom_tag}"
echo -e "\tSOURCE: ${source}"
echo -e "\tDRY_RUN: ${dryrun}"
echo -e "\tINITIAL_VERSION: ${initial_version}"
echo -e "\tTAG_CONTEXT: ${tag_context}"
echo -e "\tPRERELEASE: ${prerelease}"
echo -e "\tPRERELEASE_SUFFIX: ${suffix}"
echo -e "\tVERBOSE: ${verbose}"
echo -e "\tMAJOR_STRING_TOKEN: ${major_string_token}"
echo -e "\tMINOR_STRING_TOKEN: ${minor_string_token}"
echo -e "\tPATCH_STRING_TOKEN: ${patch_string_token}"
echo -e "\tNONE_STRING_TOKEN: ${none_string_token}"
echo -e "\tBRANCH_HISTORY: ${branch_history}"
echo -e "\tSTATE: ${state}"
echo -e "\tPR_SHA: ${pr_sha}"

# Check for changes in submodule
for dir in $modules_path; do
  if [[ -n $(git diff HEAD~1 -- $dir) ]]; then
    echo "Changes detected in submodule: $dir"
    field_num=$(echo "$dir" | tr -cd "/" | wc -c)
    field_num=$((field_num + 1))
    splitDir=$(echo $dir | cut -d "/" -f $field_num)
    echo "This is the detected module:$splitDir"
    module_prefix=$(echo $dir | cut -d "/" -f $(($field_num - 1)))
    tag_prefix=$module_prefix-$splitDir-

    # verbose, show everything
    if $verbose
    then
        set -x
    fi


    setOutput() {
        echo "${1}=${2}" >> "${GITHUB_OUTPUT}"
    }


    current_branch=$(git rev-parse --abbrev-ref HEAD)


    pre_release="$prerelease"
    IFS=',' read -ra branch <<< "$release_branches"
    for b in "${branch[@]}"; do
        # check if ${current_branch} is in ${release_branches} | exact branch match
        if [[ "$current_branch" == "$b" ]]
        then
            pre_release="false"
        fi
        # verify non specific branch names like  .* release/* if wildcard filter then =~
        if [ "$b" != "${b//[\[\]|.? +*]/}" ] && [[ "$current_branch" =~ $b ]]
        then
            pre_release="false"
        fi
    done
    echo "pre_release = $pre_release"


    # fetch tags
    git fetch --tags


    tagFmt="^$tag_prefix[0-9]+\.[0-9]+\.[0-9]+$"
    preTagFmt="^$tag_prefix[0-9]+\.[0-9]+\.[0-9]+(-$suffix\.[0-9]+)$"
    echo "this is the current tag check: $tagFmt"
    echo "this is the current pre-tag check: $preTagFmt"
    echo "start for the sorting and formatting"


    # get latest tag that looks like a semver (with or without tag_prefix)
    case "$tag_context" in
        *repo*)
            tag="$(git for-each-ref --sort=-v:refname refs/tags/${tag_prefix}* --format '%(refname:lstrip=2)' | grep -E "$tagFmt" | head -n 1)"
            pre_tag="$(git for-each-ref --sort=-v:refname refs/tags/${tag_prefix}* --format '%(refname:lstrip=2)' | grep -E "$preTagFmt" | head -n 1)"
            a="$(git for-each-ref --sort=-v:refname refs/tags/$tag_prefix* --format '%(refname:lstrip=2)')"
            echo "this/these are the related tag(s): $a"
            b="$(git for-each-ref --sort=-v:refname refs/tags/${tag_prefix}* --format '%(refname:lstrip=2)' | grep -E "$tagFmt")"
            echo "this is the latest tag: $tag"
            echo "the above are for the tag"
            c="$(git for-each-ref --sort=-v:refname refs/tags/${tag_prefix}* --format '%(refname:lstrip=2)')"
            echo "this is for the pre-tag: $c"
            d="$(git for-each-ref --sort=-v:refname refs/tags/${tag_prefix}* --format '%(refname:lstrip=2)' | grep -E "$preTagFmt")"
            echo "this is for the latest pretag: $pre_tag"
            ;;
        *branch*)
            tag="$(git tag --list --merged HEAD --sort=-v:refname | grep -E "$tagFmt" | head -n 1)"
            pre_tag="$(git tag --list --merged HEAD --sort=-v:refname | grep -E "$preTagFmt" | head -n 1)"
            ;;
        * ) echo "Unrecognised context"
            exit 1;;
    esac


    # if there are none, start tags at INITIAL_VERSION
    if [ -z "$tag" ]
    then
        if [ -n $tag_prefix ]
        then
            tag="$tag_prefix$initial_version"
            echo "if tag tag is not found then initial version is the below"
            echo "initial_version: $initial_version"
            echo "testing the tag here: $tag"
        else
            tag="$initial_version"
            echo "test tag prefix is empty"
            echo "initial_version: $initial_version"
            echo "testing the tag here: $tag"
        fi
        if [ -z "$pre_tag" ] && $pre_release
        then
            if [ -n $tag_prefix ]
            then
                pre_tag="$tag_prefix$initial_version"
            else
                pre_tag="$initial_version"
            fi
        fi
    fi


    # get current commit hash for tag
    tag_commit=$(git rev-list -n 1 "$tag")
    echo "this is the tag_commit: $tag_commit"
    # get current commit hash
    commit=$(git rev-parse HEAD)
    echo "this is the commit: $commit"
    # skip if there are no new commits for non-pre_release
    if [ "$tag_commit" == "$commit" ]
    then
        echo "No new commits since previous tag. Skipping..."
        setOutput "new_tag" "$tag"
        setOutput "tag" "$tag"
        exit 0
    fi


    # sanitize that the default_branch is set (via env var when running on PRs) else find it natively
    if [ -z "${default_branch}" ] && [ "$branch_history" == "full" ]
    then
        echo "The DEFAULT_BRANCH should be autodetected when tag-action runs on on PRs else must be defined, See: https://github.com/anothrNick/github-tag-action/pull/230, since is not defined we find it natively"
        default_branch=$(git branch -rl '*/master' '*/main' | cut -d / -f2)
        echo "default_branch=${default_branch}"
        # re check this
        if [ -z "${default_branch}" ]
        then
            echo "::error::DEFAULT_BRANCH must not be null, something has gone wrong."
            exit 1
        fi
    fi


    # get the merge commit message looking for #bumps
    declare -A history_type=(
        ["last"]="$(git show -s --format=%B)" \
        ["full"]="$(git log "${default_branch}"..HEAD --format=%B)" \
        ["compare"]="$(git log "${tag_commit}".."${commit}" --format=%B)" \
    )
    log=${history_type[${branch_history}]}
    echo "these are the logs: $log"
    printf "History:\n---\n%s\n---\n" "$log"


    stripped_tag=$(echo $tag | sed "s/^$tag_prefix//")


    case "$log" in
        *$major_string_token* ) new=$(semver -i major "$stripped_tag"); part="major";;
        *$minor_string_token* ) new=$(semver -i minor "$stripped_tag"); part="minor";;
        *$patch_string_token* ) new=$(semver -i patch "$stripped_tag"); part="patch";;
        *$none_string_token* )
            echo "Default bump was set to none. Skipping..."
            setOutput "new_tag" "$stripped_tag"
            setOutput "tag" "$stripped_tag"
            exit 0;;
        * )
            if [ "$default_semvar_bump" == "none" ]
            then
                echo "Default bump was set to none. Skipping..."
                setOutput "new_tag" "$stripped_tag"
                setOutput "tag" "$stripped_tag"
                exit 0
            else
                new=$(semver -i "${default_semvar_bump}" "$stripped_tag")
                echo "new value is"
                echo $new
                echo "below is the tag"
                echo $stripped_tag
                part=$default_semvar_bump
            fi
            ;;
    esac


    if $pre_release
    then
        # get current commit hash for tag
        pre_tag_commit=$(git rev-list -n 1 "$pre_tag")
        # skip if there are no new commits for pre_release
        if [ "$pre_tag_commit" == "$commit" ]
        then
            echo "No new commits since previous pre_tag. Skipping..."
            setOutput "new_tag" "$pre_tag"
            setOutput "tag" "$pre_tag"
            exit 0
        fi
        # already a pre-release available, bump it
        if [[ "$pre_tag" =~ $new ]] && [[ "$pre_tag" =~ $suffix ]]
        then
            if [ -n $tag_prefix ]
            then
                new=$tag_prefix$(semver -i prerelease "${pre_tag}" --preid "${suffix}")
            else
                new=$(semver -i prerelease "${pre_tag}" --preid "${suffix}")
            fi
            echo -e "Bumping ${suffix} pre-tag ${pre_tag}. New pre-tag ${new}"
        else
            if [ -n $tag_prefix ]
            then
                new="$tag_prefix$new-$suffix.0"
            else
                new="$new-$suffix.0"
            fi
            echo -e "Setting ${suffix} pre-tag ${pre_tag} - With pre-tag ${new}"
        fi
        part="pre-$part"
    else
        if [ -n $tag_prefix ]
        then
            new="$tag_prefix$new"
        fi
        echo -e "Bumping tag ${tag} - New tag ${new}"
    fi


    # as defined in readme if CUSTOM_TAG is used any semver calculations are irrelevant.
    if [ -n "$custom_tag" ]
    then
        new="$custom_tag"
    fi


    # set outputs
    setOutput "new_tag" "$new"
    setOutput "part" "$part"
    setOutput "tag" "$new" # this needs to go in v2 is breaking change
    setOutput "old_tag" "$tag"


    # dry run exit without real changes
    if $dryrun
    then
        exit 0
    fi


    # create local git tag
    git tag "$new"


    # push new tag ref to github
    dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
    full_name=$GITHUB_REPOSITORY
    git_refs_url=$(jq .repository.git_refs_url "$GITHUB_EVENT_PATH" | tr -d '"' | sed 's/{\/sha}//g')


    echo "$dt: **pushing tag $new to repo $full_name"


    author_name=$(git show $commit | grep Author | cut -d '<' -f 1)
    echo "author name:$author_name"

    git_refs_response=$(
    curl -s -X POST "$git_refs_url" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d @- << EOF

    {
      "ref": "refs/tags/$new",
      "sha": "$commit"
    }
EOF
    )

    format_date=$(echo $dt | cut -d'T' -f1)

    setOutput "outputcommit" "$commit"
    setOutput "outputauthor" "$author_name"
    setOutput "outputdate" "$format_date"

    git_ref_posted=$( echo "${git_refs_response}" | jq .ref | tr -d '"' )

    # show markdown outputs
    echo $new
    echo $commit
    echo $author_name
    echo $format_date

    echo "::debug::${git_refs_response}"
    if [ "${git_ref_posted}" = "refs/tags/${new}" ]
    then
        #exit 0
        # check if bump version worked if so then create markdown file or append
        > temp.md # clear contents of temp.md
        printf "\n" >> temp.md
        echo -e "-------------------------------------------------------------" >> temp.md
        printf "\n" >> temp.md
        printf -- "$author_name <br></br>\n [commit](https://github.com/$GITHUB_REPOSITORY/commit/$commit)\t $format_date <br></br>\n $new <br></br>\n" >> temp.md
        printf "\n" >> temp.md
        cat temp.md modules-versions.md > mynewfile.md
        mv mynewfile.md modules-versions.md

    else
        echo "::error::Tag was not created properly."
        exit 1
    fi
  fi

done
