#!/bin/bash

QUAY_NAMESPACE=(coreos prometheus)
DOCKERHUB_NAMESPACE=kuopsquay
QUAY_REPO_PRE="quay.io"
REPO_API_URL="https://quay.io/api/v1/repository?public=true&namespace="

today(){
   date +%F
}

git_init(){
    git config --global user.name "kuops"
    git config --global user.email opshsy@gmail.com
    git remote rm origin
    git remote add origin git@github.com:kuops/quay.io.git
    git pull
    if git branch -a |grep 'origin/develop' &> /dev/null ;then
        git checkout develop
        git pull origin develop
        git branch --set-upstream-to=origin/develop develop
    else
        git checkout -b develop
        git pull origin develop
    fi
}

git_commit(){
     local COMMIT_FILES_COUNT=$(git status -s|wc -l)
     local TODAY=$(today)
     if [ $COMMIT_FILES_COUNT -ne 0 ];then
        git add -A
        git commit -m "Synchronizing completion at $TODAY"
        git push -u origin develop
     fi
}

repository_list() {
    if ! [ -f repo_list.txt ];then
        for NS in  ${QUAY_NAMESPACE[@]};do
              curl -sL "${REPO_API_URL}${NS}"|jq -r '.repositories|.[]|.name'|sed "s@.*@${NS}/&@g" >> repo_list.txt
        done
        echo "get repository list done"
    else
        /bin/mv  -f repo_list.txt old_repo_list.txt
        for NS in  ${QUAY_NAMESPACE[@]};do
              curl -sL "${REPO_API_URL}${NS}"|jq -r '.repositories|.[]|.name'|sed "s@.*@${NS}/&@g" >> repo_list.txt
        done

        echo "get repository list done"
        DEL_REPO=($(diff  -B -c  old_repo_list.txt repo_list.txt |grep -Po '(?<=^\- ).+|xargs')) && \
        rm -f old_repo_list.txt
        if [ ${#DEL_REPO} -ne 0 ];then
            for i in ${DEL_REPO[@]};do
                rm -rf ${i##*/}
            done
        fi
    fi
}

generate_changelog(){
    if  ! [ -f CHANGELOG.md ];then
        echo  >> CHANGELOG.md
    fi

}

push_image(){
    QUAY_IMAGE=$1
    DOCKERHUB_IMAGE=$2
    docker pull ${QUAY_IMAGE}
    docker tag ${QUAY_IMAGE} ${DOCKERHUB_IMAGE}
    docker push ${DOCKERHUB_IMAGE}
    echo "$IMAGE_TAG_SHA" > $IMAGE_NS/$IMAGE_NAME/${i}
    sed -i  "1i\- ${DOCKERHUB_IMAGE}"  CHANGELOG.md
}

clean_images(){
     IMAGES_COUNT=$(docker image ls|wc -l)
     if [ $IMAGES_COUNT -gt 1 ];then
         docker image prune -a -f
     fi
}

clean_disk(){
    DODCKER_ROOT_DIR=$(docker info --format '{{json .}}'|jq  -r '.DockerRootDir')
    USAGE=$(df $DODCKER_ROOT_DIR|awk -F '[ %]+' 'NR>1{print $5}')
    if [ $USAGE -eq 80 ];then
        wait
        clean_images
    fi
}

main() {
    git_init
    repository_list
    generate_changelog
    TODAY=$(today)
    PROGRESS_COUNT=0
    LINE_NUM=0
    LAST_REPOSITORY=$(tail -n 1 repo_list.txt)
    while read QUAY_IMAGE_NAME;do
        let LINE_NUM++
        IMAGE_NS=${QUAY_IMAGE_NAME%/*}
        IMAGE_NAME=${QUAY_IMAGE_NAME##*/}
        IMAGE_INFO_JSON=$(curl -sL "https://quay.io/api/v1/repository/${IMAGE_NS}/${IMAGE_NAME}/tag/"|jq '.tags[]')
        TAG_INFO_JSON=$(echo "$IMAGE_INFO_JSON"|jq '{ tag: .name ,digest: .manifest_digest }')
        TAG_LIST=($(echo "$TAG_INFO_JSON"|jq -r .tag))
        if [ -f  breakpoint.txt ];then
           SAVE_DAY=$(head -n 1 breakpoint.txt)
           if [[ $SAVE_DAY != $TODAY ]];then
             :> breakpoint.txt
           else
               BREAK_LINE=$(tail -n 1 breakpoint.txt)
               if [ $LINE_NUM -lt $BREAK_LINE ];then
                   continue
               fi
           fi
        fi
        for i in ${TAG_LIST[@]};do
            QUAY_IMAGE="${QUAY_REPO_PRE}/${QUAY_IMAGE_NAME}:${i}"
            DOCKERHUB_IMAGE=${DOCKERHUB_NAMESPACE}/${IMAGE_NS}.${IMAGE_NAME}:${i}
            IMAGE_TAG_SHA=$(echo "${TAG_INFO_JSON}"|jq -r "select(.tag == \"$i\")|.digest")
            if [[ $QUAY_IMAGE_NAME == $LAST_REPOSITORY ]];then
                LAST_TAG=${TAG_LIST[-1]}
                LAST_IMAGE=${LAST_REPOSITORY}:${LAST_TAG}
                if [[ $QUAY_IMAGE  == $LAST_IMAGE ]];then
                    wait
                    clean_images
                fi
            fi
            if [ -f $IMAGE_NAME/$i ];then
                echo "$IMAGE_TAG_SHA"  > /tmp/diff.txt
                if ! diff /tmp/diff.txt $IMAGE_NAME/$i &> /dev/null ;then
                     clean_disk
                     push_image $QUAY_IMAGE $DOCKERHUB_IMAGE &
                     let PROGRESS_COUNT++
                fi
            else
                mkdir -p $IMAGE_NS/$IMAGE_NAME
                clean_disk
                push_image $QUAY_IMAGE $DOCKERHUB_IMAGE &
                let PROGRESS_COUNT++
            fi
            COUNT_WAIT=$[$PROGRESS_COUNT%20]
            if [ $COUNT_WAIT -eq 0 ];then
               wait
               clean_images
               git_commit
            fi
        done
        if [ $COUNT_WAIT -eq 0 ];then
            wait
            clean_images
            git_commit
        fi

        echo "sync image $MY_REPO/$IMAGE_NAME done."
        echo -e "$TODAY\n$LINE_NUM" > breakpoint.txt
    done < repo_list.txt 
    sed -i "1i-------------------------------at $(date +'%F %T') sync image repositorys-------------------------------"  CHANGELOG.md
    git_commit
}

main
