package io.fogcache.edge.demo;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

/**
 * Minimal demo cache surface for local smoke tests and demos (milestone 02.6).
 *
 * <p>Serves a few stable fixture objects whose bytes are generated deterministically with the same
 * algorithm as {@code seed/tools/regenerate.ps1}, so checksums match the seed manifest. The first
 * request for an object is a {@code miss} (computed and stored), every later request is a {@code
 * hit} (served from an in-memory map). This is a placeholder for the real cache implementation and
 * is intentionally tiny.
 */
@RestController
public class DemoCacheController {

  private static final Map<String, DemoObject> OBJECTS =
      Map.of(
          "object-hello",
              textObject("object-hello", "text/plain", "hello from fogcache seed fixture\n"),
          "object-config",
              textObject(
                  "object-config",
                  "application/json",
                  "{\"region\":\"us-east-1\",\"tier\":\"standard\",\"ttl\":60,"
                      + "\"cacheable\":true}"),
          "object-page",
              textObject(
                  "object-page",
                  "text/html",
                  "<!DOCTYPE html>\n"
                      + "<html><head><title>FogCache demo page</title></head>\n"
                      + "<body><h1>FogCache deterministic fixture</h1>\n"
                      + "<p>This page is generated deterministically for local demos.</p>"
                      + "</body></html>"),
          "object-image", binaryObject("object-image", "image/png", 256 * 1024));

  private final ConcurrentHashMap<String, DemoObject> cache = new ConcurrentHashMap<>();
  private final Counter hits;
  private final Counter misses;

  public DemoCacheController(MeterRegistry meterRegistry) {
    this.hits = meterRegistry.counter("fogcache.demo.cache.hits");
    this.misses = meterRegistry.counter("fogcache.demo.cache.misses");
  }

  /** Serves a fixture object with a miss/hit status header. */
  @GetMapping(path = "/demo/cache/{uid}", produces = MediaType.APPLICATION_OCTET_STREAM_VALUE)
  public ResponseEntity<byte[]> get(@PathVariable String uid) {
    DemoObject source = OBJECTS.get(uid);
    if (source == null) {
      return ResponseEntity.notFound().build();
    }
    DemoObject hit = cache.get(uid);
    if (hit != null) {
      hits.increment();
      return serve(hit, "hit");
    }
    misses.increment();
    DemoObject stored = source;
    cache.put(uid, stored);
    return serve(stored, "miss");
  }

  /** Evicts an object so smoke runs can start from a deterministic cold state. */
  @DeleteMapping("/demo/cache/{uid}")
  public ResponseEntity<Void> evict(@PathVariable String uid) {
    cache.remove(uid);
    return ResponseEntity.noContent().build();
  }

  private static ResponseEntity<byte[]> serve(DemoObject object, String status) {
    return ResponseEntity.ok()
        .header("X-FogCache-Status", status)
        .header("X-FogCache-Object", object.uid)
        .header("X-FogCache-Sha256", object.sha256)
        .contentType(MediaType.parseMediaType(object.contentType))
        .contentLength(object.bytes.length)
        .body(object.bytes);
  }

  private static DemoObject textObject(String uid, String contentType, String content) {
    byte[] bytes = content.getBytes(StandardCharsets.UTF_8);
    return new DemoObject(uid, contentType, bytes, sha256Hex(bytes));
  }

  private static DemoObject binaryObject(String uid, String contentType, int size) {
    byte[] bytes = deterministicBytes(uid, size);
    return new DemoObject(uid, contentType, bytes, sha256Hex(bytes));
  }

  /** Reproduces {@code Get-DeterministicBytes} from seed/tools/regenerate.ps1. */
  static byte[] deterministicBytes(String uid, int size) {
    try {
      MessageDigest digest = MessageDigest.getInstance("SHA-256");
      byte[] out = new byte[size];
      byte[] block = new byte[32];
      int written = 0;
      for (int blockIndex = 0; written < size; blockIndex++) {
        digest.reset();
        digest.update((uid + "_" + blockIndex).getBytes(StandardCharsets.UTF_8));
        byte[] hash = digest.digest();
        System.arraycopy(hash, 0, block, 0, hash.length);
        System.arraycopy(block, 0, out, written, Math.min(32, size - written));
        written += 32;
      }
      return out;
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException("SHA-256 must be available", e);
    }
  }

  private static String sha256Hex(byte[] bytes) {
    try {
      MessageDigest digest = MessageDigest.getInstance("SHA-256");
      return HexFormat.of().formatHex(digest.digest(bytes));
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException("SHA-256 must be available", e);
    }
  }

  private record DemoObject(String uid, String contentType, byte[] bytes, String sha256) {}
}
