package com.choisangjin.txtviewer

import org.junit.Test

class DeletePolicyTest {
    private fun check(tree: Boolean = true, root: Boolean = false, directory: Boolean = false,
                      name: String = "소설.TXT", expected: String = "소설.TXT",
                      supported: Boolean = true, write: Boolean = true) =
        DeletePolicy.requireAllowed(tree, root, directory, name, expected, supported, write)
    @Test fun allowsConfirmedWritableTxt() { check() }
    @Test(expected = IllegalArgumentException::class) fun rejectsDifferentTree() { check(tree = false) }
    @Test(expected = IllegalArgumentException::class) fun rejectsTreeRoot() { check(root = true) }
    @Test(expected = IllegalArgumentException::class) fun rejectsDirectoriesEvenWithTxtNames() { check(directory = true) }
    @Test(expected = IllegalArgumentException::class) fun rejectsOtherFileTypes() { check(name = "원본.pdf", expected = "원본.pdf") }
    @Test(expected = IllegalArgumentException::class) fun rejectsRenamedDocuments() { check(name = "바뀐.txt") }
    @Test(expected = IllegalStateException::class) fun rejectsReadOnlyGrants() { check(write = false) }
    @Test(expected = IllegalStateException::class) fun rejectsUnsupportedProviders() { check(supported = false) }
}
