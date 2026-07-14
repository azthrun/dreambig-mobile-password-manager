package com.dreambig.password_manager

import android.app.assist.AssistStructure
import android.view.View
import android.view.autofill.AutofillId

/** What a single fill request is asking to fill: which app/site, and
 * which on-screen fields are fillable, split by kind so a match's
 * identifier (username/email) and secret (password) each land in the
 * right field rather than both being stuffed with the same value. */
data class AutofillTarget(
    val packageName: String,
    val webDomain: String?,
    val identifierFields: List<AutofillId>,
    val passwordFields: List<AutofillId>,
) {
    /** All fillable fields regardless of kind — used only to decide
     * whether this request has anything worth responding to. */
    val fields: List<AutofillId>
        get() = identifierFields + passwordFields
}

/**
 * Walks an [AssistStructure] handed to
 * [PasswordManagerAutofillService.onFillRequest] to find:
 *  - the requesting app's package name (always present) and, for
 *    browser-hosted forms, the web domain of the page (present when the
 *    browser populates `ViewNode.webDomain`, e.g. Chrome/most Autofill-
 *    compatible browsers — not guaranteed for every browser);
 *  - the [AutofillId]s of fields worth offering a suggestion for (only
 *    username/email/password-hinted fields — deliberately not every
 *    editable field on screen, to avoid offering a credential fill on
 *    unrelated form fields).
 *
 * **Untested against a real [AssistStructure]**: there is no
 * Android emulator/device available in this build sandbox. The traversal
 * shape (recursive walk of window → view node tree, checking
 * `autofillHints`) mirrors the structure Android's own `AutofillService`
 * sample app and documentation describe, but has not been exercised
 * on-device — see `PasswordManagerAutofillService`'s doc comment for the
 * full caveat on what is/isn't verified in this Phase 8 change.
 */
object AutofillStructureParser {
    fun parse(structure: AssistStructure): AutofillTarget {
        val identifierFields = mutableListOf<AutofillId>()
        val passwordFields = mutableListOf<AutofillId>()
        var webDomain: String? = null
        val packageName = structure.activityComponent?.packageName ?: ""

        for (i in 0 until structure.windowNodeCount) {
            val root = structure.getWindowNodeAt(i).rootViewNode
            if (webDomain == null) {
                webDomain = findWebDomain(root)
            }
            collectFillableFields(root, identifierFields, passwordFields)
        }

        return AutofillTarget(
            packageName = packageName,
            webDomain = webDomain,
            identifierFields = identifierFields,
            passwordFields = passwordFields,
        )
    }

    private fun findWebDomain(node: AssistStructure.ViewNode): String? {
        node.webDomain?.let { if (it.isNotBlank()) return it }
        for (i in 0 until node.childCount) {
            findWebDomain(node.getChildAt(i))?.let { return it }
        }
        return null
    }

    private fun collectFillableFields(
        node: AssistStructure.ViewNode,
        identifierFields: MutableList<AutofillId>,
        passwordFields: MutableList<AutofillId>,
    ) {
        val id = node.autofillId
        val hints = node.autofillHints
        if (id != null && hints != null) {
            if (hints.any { it == View.AUTOFILL_HINT_PASSWORD }) {
                passwordFields.add(id)
            } else if (hints.any(::isIdentifierHint)) {
                identifierFields.add(id)
            }
        }
        for (i in 0 until node.childCount) {
            collectFillableFields(node.getChildAt(i), identifierFields, passwordFields)
        }
    }

    private fun isIdentifierHint(hint: String): Boolean {
        return hint == View.AUTOFILL_HINT_USERNAME ||
            hint == View.AUTOFILL_HINT_EMAIL_ADDRESS
    }
}
