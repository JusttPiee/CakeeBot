interface SearchBoxProps {
  value: string;
  onChange: (value: string) => void;
  /** Shown while the box is empty, and read by screen readers as the box's name. */
  placeholder: string;
}

/** A text box for filtering a list. The parent keeps the text (a "controlled" input). */
export function SearchBox({ value, onChange, placeholder }: SearchBoxProps) {
  return (
    <input
      type="search"
      value={value}
      placeholder={placeholder}
      aria-label={placeholder}
      onChange={(event) => onChange(event.target.value)}
    />
  );
}
