package com.example.ps4_sender

import androidx.core.content.FileProvider

/** Own subclass so it never clashes with a FileProvider declared by a plugin. */
class UpdateFileProvider : FileProvider()
