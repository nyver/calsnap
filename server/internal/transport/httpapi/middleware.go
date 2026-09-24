package httpapi

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"regexp"
	"runtime/debug"
	"strings"
	"time"

	"github.com/google/uuid"
)

// requestIDPattern is the accepted shape of a client-supplied X-Request-Id.
var requestIDPattern = regexp.MustCompile(`^[A-Za-z0-9-]{8,64}$`)

type ctxKey int

const (
	keyRequestID ctxKey = iota
	keyInfo
)

// requestInfo carries per-request facts from handlers to the access log.
// It never holds content: only sizes, counts and codes.
type requestInfo struct {
	clientID    bool // the client supplied a valid request id
	errorCode   string
	imageBytes  int
	itemCount   int
	hasItemInfo bool
}

func requestIDFrom(ctx context.Context) string {
	id, _ := ctx.Value(keyRequestID).(string)
	return id
}

func infoFrom(ctx context.Context) *requestInfo {
	in, _ := ctx.Value(keyInfo).(*requestInfo)
	return in
}

// statusRecorder captures the status and size of a response.
type statusRecorder struct {
	http.ResponseWriter
	status      int
	bytes       int
	wroteHeader bool
}

func (s *statusRecorder) WriteHeader(code int) {
	if s.wroteHeader {
		return
	}
	s.wroteHeader = true
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusRecorder) Write(p []byte) (int, error) {
	if !s.wroteHeader {
		s.WriteHeader(http.StatusOK)
	}
	n, err := s.ResponseWriter.Write(p)
	s.bytes += n
	return n, err
}

// Unwrap lets http.ResponseController reach the underlying writer.
func (s *statusRecorder) Unwrap() http.ResponseWriter { return s.ResponseWriter }

// requestIDMiddleware assigns the effective request id and the per-request info.
func requestIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-Id")
		in := &requestInfo{clientID: requestIDPattern.MatchString(id)}
		if !in.clientID {
			id = uuid.Must(uuid.NewV7()).String()
		}
		w.Header().Set("X-Request-Id", id)
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "no-store")
		ctx := context.WithValue(r.Context(), keyRequestID, id)
		ctx = context.WithValue(ctx, keyInfo, in)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// observeMiddleware writes the structured access log and records metrics.
// The route label is the registered pattern, so its cardinality is fixed.
func observeMiddleware(log *slog.Logger, obs Observer, now func() time.Time, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := now()
		rec := &statusRecorder{ResponseWriter: w}
		next.ServeHTTP(rec, r)
		if !rec.wroteHeader {
			rec.WriteHeader(http.StatusOK)
		}

		elapsed := now().Sub(start)
		route := routeLabel(r)
		obs.ObserveRequest(route, r.Method, rec.status, elapsed.Seconds())

		attrs := []any{
			"request_id", requestIDFrom(r.Context()),
			"method", r.Method,
			"route", route,
			"status", rec.status,
			"duration_ms", elapsed.Milliseconds(),
			"bytes_out", rec.bytes,
		}
		if in := infoFrom(r.Context()); in != nil {
			if in.imageBytes > 0 {
				attrs = append(attrs, "image_bytes", in.imageBytes)
			}
			if in.hasItemInfo {
				attrs = append(attrs, "items", in.itemCount)
			}
			if in.errorCode != "" {
				attrs = append(attrs, "error_code", in.errorCode)
			}
		}
		level := slog.LevelInfo
		if rec.status >= 500 {
			level = slog.LevelWarn
		}
		log.Log(r.Context(), level, "request", attrs...)
	})
}

// routeLabel returns the path part of the matched mux pattern.
func routeLabel(r *http.Request) string {
	p := r.Pattern
	if p == "" {
		return "unmatched"
	}
	if _, path, ok := strings.Cut(p, " "); ok {
		return path
	}
	return p
}

// recoverMiddleware turns panics into INTERNAL_ERROR responses.
func recoverMiddleware(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() { //nolint:contextcheck // the request carries the context; recover runs in a deferred closure
			v := recover()
			if v == nil {
				return
			}
			if v == http.ErrAbortHandler { //nolint:errorlint // sentinel panic value, compared by identity
				panic(v)
			}
			log.ErrorContext(r.Context(), "panic while handling request",
				"request_id", requestIDFrom(r.Context()),
				"panic", fmt.Sprint(v),
				"stack", string(debug.Stack()))
			if rec, ok := w.(*statusRecorder); ok && rec.wroteHeader {
				return
			}
			writeAPIError(w, r, newError(CodeInternalError))
		}()
		next.ServeHTTP(w, r)
	})
}
