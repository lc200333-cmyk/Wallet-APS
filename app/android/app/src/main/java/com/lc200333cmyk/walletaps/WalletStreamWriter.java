package com.lc200333cmyk.walletaps;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.OutputStream;

/** Stream-only SAF write, used only after MainActivity safeguards the old data. */
public final class WalletStreamWriter {
    private WalletStreamWriter() {}

    @FunctionalInterface
    public interface Opener {
        OutputStream open(String mode) throws IOException;
    }

    public static void write(File source, Opener opener) throws IOException {
        OutputStream opened;
        try {
            opened = open(opener, "wt");
        } catch (IOException | IllegalArgumentException | UnsupportedOperationException first) {
            // Retry only opening the stream. A transfer/flush/close failure must
            // be reported, not hidden by opening and truncating the file again.
            try {
                opened = open(opener, "w");
            } catch (IOException | RuntimeException second) {
                second.addSuppressed(first);
                throw second;
            }
        }
        try (OutputStream output = opened; FileInputStream input = new FileInputStream(source)) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) {
                output.write(buffer, 0, count);
            }
            output.flush();
        }
    }

    private static OutputStream open(Opener opener, String mode) throws IOException {
        OutputStream stream = opener.open(mode);
        if (stream == null) throw new IOException("Cloud provider did not open a wallet write stream");
        return stream;
    }
}
