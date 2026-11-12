package com.deepseek.harness.app

import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Message
import android.view.KeyEvent
import android.webkit.ClientCertRequest
import android.webkit.HttpAuthHandler
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient

/**
 * A WebViewClient that keeps the process alive when a renderer dies, and
 * forwards every other callback to the plugin's own client unchanged.
 *
 * The platform contract is that a WebView whose renderer is gone must not be
 * reused: returning true from [onRenderProcessGone] keeps the app running
 * instead of being killed with the renderer, and [onGone] tells the Dart side
 * to recreate the page that owned the dead view. This class installs on API
 * 26+ only, which is where both the callback and `WebView.getWebViewClient()`
 * exist; the delegate therefore is the plugin's client and stays the owner of
 * page behavior.
 */
class RendererDeathGuard(
    private val delegate: WebViewClient,
    private val onGone: (didCrash: Boolean, priority: Int) -> Unit,
) : WebViewClient() {
    override fun onRenderProcessGone(view: WebView?, detail: RenderProcessGoneDetail): Boolean {
        onGone(detail.didCrash(), detail.rendererPriorityAtExit())
        return true
    }

    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
        delegate.onPageStarted(view, url, favicon)
    }

    override fun onPageFinished(view: WebView?, url: String?) {
        delegate.onPageFinished(view, url)
    }

    override fun onReceivedHttpError(
        view: WebView?,
        request: WebResourceRequest?,
        errorResponse: WebResourceResponse?,
    ) {
        delegate.onReceivedHttpError(view, request, errorResponse)
    }

    override fun onReceivedError(
        view: WebView?,
        request: WebResourceRequest?,
        error: WebResourceError?,
    ) {
        delegate.onReceivedError(view, request, error)
    }

    override fun shouldOverrideUrlLoading(
        view: WebView?,
        request: WebResourceRequest?,
    ): Boolean = delegate.shouldOverrideUrlLoading(view, request)

    override fun doUpdateVisitedHistory(view: WebView?, url: String?, isReload: Boolean) {
        delegate.doUpdateVisitedHistory(view, url, isReload)
    }

    override fun onReceivedHttpAuthRequest(
        view: WebView?,
        handler: HttpAuthHandler?,
        host: String?,
        realm: String?,
    ) {
        delegate.onReceivedHttpAuthRequest(view, handler, host, realm)
    }

    override fun onFormResubmission(view: WebView?, dontResend: Message?, resend: Message?) {
        delegate.onFormResubmission(view, dontResend, resend)
    }

    override fun onLoadResource(view: WebView?, url: String?) {
        delegate.onLoadResource(view, url)
    }

    override fun onPageCommitVisible(view: WebView?, url: String?) {
        delegate.onPageCommitVisible(view, url)
    }

    override fun onReceivedClientCertRequest(view: WebView?, request: ClientCertRequest?) {
        delegate.onReceivedClientCertRequest(view, request)
    }

    override fun onReceivedLoginRequest(
        view: WebView?,
        realm: String?,
        account: String?,
        args: String?,
    ) {
        delegate.onReceivedLoginRequest(view, realm, account, args)
    }

    override fun onReceivedSslError(
        view: WebView?,
        handler: SslErrorHandler?,
        error: SslError?,
    ) {
        delegate.onReceivedSslError(view, handler, error)
    }

    override fun onScaleChanged(view: WebView?, oldScale: Float, newScale: Float) {
        delegate.onScaleChanged(view, oldScale, newScale)
    }

    override fun onUnhandledKeyEvent(view: WebView?, event: KeyEvent?) {
        delegate.onUnhandledKeyEvent(view, event)
    }
}
