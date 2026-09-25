package com.bucks.app.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri

/** Hands off to the phone's own dialer, SMS and share apps; none of these need a permission. */
fun dial(ctx: Context, phone: String) { runCatching { ctx.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:${fullNumber(phone)}"))) } }
fun sms(ctx: Context, phone: String) { runCatching { ctx.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:${fullNumber(phone)}"))) } }
fun shareText(ctx: Context, text: String) { runCatching { ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), null)) } }
/** Profiles store 10-digit Indian numbers; short codes like 112 pass through. */
private fun fullNumber(p: String) = p.filter { it.isDigit() || it == '+' }.let { if (it.length == 10) "+91$it" else it }

fun Context.findActivity(): Activity? { var c: Context = this; while (c is ContextWrapper) { if (c is Activity) return c; c = c.baseContext }; return null }
