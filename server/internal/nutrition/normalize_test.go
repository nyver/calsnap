package nutrition

import "testing"

func TestNormalizerKey(t *testing.T) {
	t.Parallel()

	n := NewNormalizer([]string{"grilled", "boiled", "fried", "sliced", "fresh", "жареная", "свежие"})
	tests := []struct {
		in, want string
	}{
		{"Grilled  Chicken Breast!", "chicken_breast"},
		{"  chicken   breast  ", "chicken_breast"},
		{"Stir-fried noodles", "stir_noodles"},
		{"grandma's special casserole", "grandmas_special_casserole"},
		{"Fresh SLICED Tomato", "tomato"},
		{"fried", "fried"},
		{"Boiled, fried", "boiled_fried"},
		{"Жареная Курица", "курица"},
		{"Свежие огурцы", "огурцы"},
		{"Свёкла", "свекла"},
		{"rice (cooked)", "rice_cooked"},
		{"", ""},
		{"!!!", ""},
		{"Café  Latte", "café_latte"},
	}
	for _, tt := range tests {
		if got := n.Key(tt.in); got != tt.want {
			t.Errorf("Key(%q) = %q, want %q", tt.in, got, tt.want)
		}
	}
}

func TestNormalizerIsDeterministic(t *testing.T) {
	t.Parallel()

	n := NewNormalizer([]string{"fried"})
	first := n.Key("Fried  Egg!")
	for range 100 {
		if got := n.Key("Fried  Egg!"); got != first {
			t.Fatalf("non-deterministic: %q vs %q", got, first)
		}
	}
}

func TestFullKeepsModifiers(t *testing.T) {
	t.Parallel()

	if got := Full("Fried Rice!"); got != "fried_rice" {
		t.Errorf("Full = %q", got)
	}
}
