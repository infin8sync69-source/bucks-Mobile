package com.bucks.app

import androidx.core.content.FileProvider

/** Hands cached attachments (PDFs, documents) to the phone's own viewers. A separate class from the debug updater's provider so both can exist. */
class FilesProvider : FileProvider()
