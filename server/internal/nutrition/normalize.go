// Package nutrition holds the bundled nutrition catalog, name normalization
// and the matching pipeline that resolves recognized food names to profiles.
package nutrition

import (
	"strings"
	"unicode"
)

// Normalizer converts free-form food names into stable snake_case keys.
type Normalizer struct {
	modifiers map[string]struct{}
}

// NewNormalizer creates a Normalizer that drops the given cooking and serving
// modifiers (already lowercase) when computing Key.
func NewNormalizer(modifiers []string) *Normalizer {
	set := make(map[string]struct{}, len(modifiers))
	for _, m := range modifiers {
		set[strings.ToLower(m)] = struct{}{}
	}
	return &Normalizer{modifiers: set}
}

// Tokens lowercases name, unifies "ё" with "е", drops apostrophes and splits on
// every other non-letter, non-digit character.
func Tokens(name string) []string {
	name = strings.ToLower(name)
	name = strings.NewReplacer("ё", "е", "'", "", "’", "", "ʼ", "", "`", "").Replace(name)
	return strings.FieldsFunc(name, func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r) && !unicode.IsMark(r)
	})
}

// Full returns the snake_case key that keeps modifiers. Catalog ids, names and
// aliases are registered under this form, so entries such as "fried rice"
// stay distinct from "rice".
func Full(name string) string { return strings.Join(Tokens(name), "_") }

// Key returns the normalized key of a name: modifiers are removed and the rest
// is joined with underscores. When the name consists of modifiers only, they are
// kept so that the key is never empty for a non-empty name.
func (n *Normalizer) Key(name string) string {
	return strings.Join(n.keyTokens(name), "_")
}

func (n *Normalizer) keyTokens(name string) []string {
	all := Tokens(name)
	kept := make([]string, 0, len(all))
	for _, t := range all {
		if _, drop := n.modifiers[t]; !drop {
			kept = append(kept, t)
		}
	}
	if len(kept) == 0 {
		return all
	}
	return kept
}
