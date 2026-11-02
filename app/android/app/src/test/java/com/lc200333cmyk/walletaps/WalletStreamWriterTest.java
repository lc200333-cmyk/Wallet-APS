package com.lc200333cmyk.walletaps;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/** Standalone JDK harness: no Android device or extra test dependency required. */
public final class WalletStreamWriterTest {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        File source = File.createTempFile("wallet-stream-", ".swl");
        byte[] bytes = new byte[32769];
        for (int i = 0; i < bytes.length; i++) bytes[i] = (byte) (i * 31);
        Files.write(source.toPath(), bytes);
        try {
            // A stream-only provider accepting wt gets the entire snapshot.
            List<String> modes = new ArrayList<>();
            ByteArrayOutputStream target = new ByteArrayOutputStream();
            WalletStreamWriter.write(source, mode -> { modes.add(mode); return target; });
            check(modes.equals(Arrays.asList("wt")), "wt must be preferred");
            check(Arrays.equals(bytes, target.toByteArray()), "complete snapshot expected");

            // Drive-like provider rejects truncation suffix, but accepts w.
            for (int rejection = 0; rejection < 3; rejection++) {
                final int kind = rejection;
                modes.clear();
                target.reset();
                WalletStreamWriter.write(source, mode -> {
                    modes.add(mode);
                    if (mode.equals("wt")) {
                        if (kind == 0) throw new IOException("Unsupported mode: wt");
                        if (kind == 1) throw new IllegalArgumentException("Unsupported mode: wt");
                        return null;
                    }
                    return target;
                });
                check(modes.equals(Arrays.asList("wt", "w")), "w fallback expected");
                check(Arrays.equals(bytes, target.toByteArray()), "fallback lost bytes");
            }

            // No retries once bytes may have been written, even on close failure.
            for (boolean failOnClose : new boolean[] {false, true}) {
                modes.clear();
                boolean failed = false;
                try {
                    WalletStreamWriter.write(source, mode -> {
                        modes.add(mode);
                        return new OutputStream() {
                            @Override public void write(int value) throws IOException {
                                if (!failOnClose) throw new IOException("connection lost");
                            }
                            @Override public void close() throws IOException {
                                if (failOnClose) throw new IOException("upload commit failed");
                            }
                        };
                    });
                } catch (IOException expected) { failed = true; }
                check(failed, "transfer/close failure must be reported");
                check(modes.equals(Arrays.asList("wt")), "must not reopen after transfer failure");
            }

            modes.clear();
            try {
                WalletStreamWriter.write(source, mode -> {
                    modes.add(mode);
                    throw new IOException("rejected " + mode);
                });
                throw new AssertionError("expected both modes to fail");
            } catch (IOException expected) {
                check(expected.getSuppressed().length == 1, "preserve first open error");
            }
            check(modes.equals(Arrays.asList("wt", "w")), "exactly two opens allowed");

            modes.clear();
            try {
                WalletStreamWriter.write(source, mode -> {
                    modes.add(mode);
                    throw new SecurityException("permission revoked");
                });
                throw new AssertionError("permission failure must propagate");
            } catch (SecurityException expected) {
                check(modes.equals(Arrays.asList("wt")), "do not retry revoked permission");
            }
            check(Arrays.equals(bytes, Files.readAllBytes(source.toPath())), "source must remain unchanged");
            System.out.println("WalletStreamWriterTest: 8 scenarios passed");
        } finally {
            Files.deleteIfExists(source.toPath());
        }
    }
}
