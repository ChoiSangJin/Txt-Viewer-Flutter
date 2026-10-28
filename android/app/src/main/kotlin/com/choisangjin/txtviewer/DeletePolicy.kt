package com.choisangjin.txtviewer

/** Only a confirmed, unchanged TXT document in its selected tree is deletable. */
object DeletePolicy {
    fun requireAllowed(sameTree: Boolean, isRoot: Boolean, isDirectory: Boolean,
                       name: String, expectedName: String, supportsDelete: Boolean, canWrite: Boolean) {
        require(sameTree && !isRoot) { "선택한 폴더 안의 파일만 삭제할 수 있습니다." }
        require(!isDirectory && name.endsWith(".txt", true)) { "TXT 파일만 삭제할 수 있습니다. 폴더는 삭제하지 않습니다." }
        require(name == expectedName) { "파일 이름이 변경됐습니다. 새로고침 후 다시 선택해 주세요." }
        check(canWrite) { "폴더 삭제 권한을 다시 허용해 주세요." }
        check(supportsDelete) { "이 저장소는 파일 삭제를 지원하지 않습니다." }
    }
}
