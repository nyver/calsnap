package prompt_test

import (
	"strings"
	"testing"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/vision/prompt"
)

func TestUserDescribesTheAttachedPhotos(t *testing.T) {
	t.Parallel()

	single := prompt.User(analysis.RequestContext{Locale: analysis.LocaleRU, PlateDiameterCm: 26})
	for _, want := range []string{"Russian", "26 cm"} {
		if !strings.Contains(single, want) {
			t.Errorf("single-photo prompt lacks %q: %s", want, single)
		}
	}
	if strings.Contains(single, "side") {
		t.Errorf("single-photo prompt must not mention a side view: %s", single)
	}

	two := prompt.User(analysis.RequestContext{Locale: analysis.LocaleEN, SideImage: &analysis.Image{}})
	for _, want := range []string{"first was taken from above", "second from the side", "once"} {
		if !strings.Contains(two, want) {
			t.Errorf("two-photo prompt lacks %q: %s", want, two)
		}
	}
}
