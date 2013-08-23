/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// This file is a Mako template: http://www.makotemplates.org/

use std::ascii::StrAsciiExt;
use errors::{ErrorLoggerIterator, log_css_error};
pub use std::iterator;
pub use cssparser::*;
pub use CSSColor = cssparser::Color;
pub use parsing_utils::*;
pub use self::common_types::*;

pub mod common_types;


<%!

def to_rust_ident(name):
    name = name.replace("-", "_")
    if name in ["static"]:  # Rust keywords
        name += "_"
    return name

class Longhand(object):
    def __init__(self, name):
        self.name = name
        self.ident = to_rust_ident(name)


class Shorthand(object):
    def __init__(self, name, sub_properties):
        self.name = name
        self.ident = to_rust_ident(name)
        self.sub_properties = [Longhand(s) for s in sub_properties]

LONGHANDS = []
SHORTHANDS = []
INHERITED = set()

%>

pub mod longhands {
    pub use super::*;

    <%def name="longhand(name, inherited=False)">
    <%
        property = Longhand(name)
        LONGHANDS.append(property)
        if inherited:
            INHERITED.add(name)
    %>
        pub mod ${property.ident} {
            use super::*;
            ${caller.body()}
        }
    </%def>

    <%def name="single_component_value(name, inherited=False)">
        <%self:longhand name="${name}" inherited="${inherited}">
            ${caller.body()}
            pub fn parse(input: &[ComponentValue]) -> Option<SpecifiedValue> {
                one_component_value(input).chain(from_component_value)
            }
        </%self:longhand>
    </%def>

    <%def name="single_keyword(name, values, inherited=False)">
        <%self:single_component_value name="${name}" inherited="${inherited}">
            pub enum SpecifiedValue {
                % for value in values.split():
                    ${to_rust_ident(value)},
                % endfor
            }
            pub fn from_component_value(v: &ComponentValue) -> Option<SpecifiedValue> {
                do get_ident_lower(v).chain |keyword| {
                    match keyword.as_slice() {
                        % for value in values.split():
                            "${value}" => Some(${to_rust_ident(value)}),
                        % endfor
                        _ => None,
                    }
                }
            }
        </%self:single_component_value>
    </%def>

    <%def name="predefined_function(name, result_type, function, inherited=False)">
        <%self:longhand name="${name}" inherited="${inherited}">
            pub type SpecifiedValue = ${result_type};
            pub fn parse(input: &[ComponentValue]) -> Option<SpecifiedValue> {
                one_component_value(input).chain(${function})
            }
        </%self:longhand>
    </%def>

    <%def name="predefined_type(name, type, inherited=False)">
        ${predefined_function(name, type, type + "::parse", inherited)}
    </%def>


    // CSS 2.1, Section 8 - Box model

    ${predefined_function("margin-top", "specified::LengthOrPercentageOrAuto",
                                        "specified::LengthOrPercentageOrAuto::parse")}
    ${predefined_function("margin-right", "specified::LengthOrPercentageOrAuto",
                                          "specified::LengthOrPercentageOrAuto::parse")}
    ${predefined_function("margin-bottom", "specified::LengthOrPercentageOrAuto",
                                           "specified::LengthOrPercentageOrAuto::parse")}
    ${predefined_function("margin-left", "specified::LengthOrPercentageOrAuto",
                                         "specified::LengthOrPercentageOrAuto::parse")}

    ${predefined_function("padding-top",
        "specified::LengthOrPercentage",
        "specified::LengthOrPercentage::parse_non_negative")}
    ${predefined_function("padding-right",
        "specified::LengthOrPercentage",
        "specified::LengthOrPercentage::parse_non_negative")}
    ${predefined_function("padding-bottom",
        "specified::LengthOrPercentage",
        "specified::LengthOrPercentage::parse_non_negative")}
    ${predefined_function("padding-left",
        "specified::LengthOrPercentage",
        "specified::LengthOrPercentage::parse_non_negative")}

    ${predefined_type("border-top-color", "CSSColor")}
    ${predefined_type("border-right-color", "CSSColor")}
    ${predefined_type("border-bottom-color", "CSSColor")}
    ${predefined_type("border-left-color", "CSSColor")}

    pub enum BorderStyle {
        BorderStyleSolid,
        // Uncomment when supported
//        BorderStyleDotted,
//        BorderStyleDashed,
//        BorderStyleDouble,
//        BorderStyleGroove,
//        BorderStyleRidge,
//        BorderStyleInset,
//        BorderStyleOutset,
//        BorderStyleHidden,
        BorderStyleNone,
    }
    impl BorderStyle {
        pub fn parse(input: &ComponentValue) -> Option<BorderStyle> {
            do get_ident_lower(input).chain |keyword| {
                match keyword.as_slice() {
                    "solid" => Some(BorderStyleSolid),
                    "none" => Some(BorderStyleNone),
                    _ => None,
                }
            }
        }
    }
    ${predefined_type("border-top-style", "BorderStyle")}
    ${predefined_type("border-right-style", "BorderStyle")}
    ${predefined_type("border-bottom-style", "BorderStyle")}
    ${predefined_type("border-left-style", "BorderStyle")}

    pub fn parse_border_width(component_value: &ComponentValue) -> Option<specified::Length> {
        match component_value {
            &Ident(ref value) => match value.to_ascii_lower().as_slice() {
                "thin" => Some(specified::Length::from_px(1.)),
                "medium" => Some(specified::Length::from_px(3.)),
                "thick" => Some(specified::Length::from_px(5.)),
                _ => None
            },
            _ => specified::Length::parse_non_negative(component_value)
        }
    }
    ${predefined_function("border-top-width", "specified::Length", "parse_border_width")}
    ${predefined_function("border-right-width", "specified::Length", "parse_border_width")}
    ${predefined_function("border-bottom-width", "specified::Length", "parse_border_width")}
    ${predefined_function("border-left-width", "specified::Length", "parse_border_width")}

    // CSS 2.1, Section 9 - Visual formatting model

    // TODO: don't parse values we don't support
    ${single_keyword("display",
        "inline block list-item inline-block none "
    )}
//        "table inline-table table-row-group table-header-group table-footer-group "
//        "table-row table-column-group table-column table-cell table-caption"

    ${single_keyword("position", "static absolute relative fixed")}
    ${single_keyword("float", "left right none")}
    ${single_keyword("clear", "left right none both")}

    // CSS 2.1, Section 10 - Visual formatting model details

    ${predefined_function("width",
        "specified::LengthOrPercentageOrAuto",
        "specified::LengthOrPercentageOrAuto::parse_non_negative")}
    ${predefined_function("height",
        "specified::LengthOrPercentageOrAuto",
        "specified::LengthOrPercentageOrAuto::parse_non_negative")}

    <%self:single_component_value name="line-height">
        pub enum SpecifiedValue {
            Normal,
            Length(specified::Length),
            Percentage(Float),
            Number(Float),
        }
        /// normal | <number> | <length> | <percentage>
        pub fn from_component_value(input: &ComponentValue) -> Option<SpecifiedValue> {
            match input {
                &ast::Number(ref value) if value.value >= 0.
                => Some(Number(value.value)),
                &ast::Percentage(ref value) if value.value >= 0.
                => Some(Percentage(value.value)),
                &Dimension(ref value, ref unit) if value.value >= 0.
                => specified::Length::parse_dimension(value.value, unit.as_slice())
                    .map_move(Length),
                &Ident(ref value) if value.eq_ignore_ascii_case("auto")
                => Some(Normal),
                _ => None,
            }
        }
    </%self:single_component_value>

    // CSS 2.1, Section 11 - Visual effects

    // CSS 2.1, Section 12 - Generated content, automatic numbering, and lists

    // CSS 2.1, Section 13 - Paged media

    // CSS 2.1, Section 14 - Colors and Backgrounds

    ${predefined_type("background-color", "CSSColor")}
    ${predefined_type("color", "CSSColor", inherited=True)}

    // CSS 2.1, Section 15 - Fonts

    <%self:longhand name="font-family" inherited="True">
        enum FontFamily {
            FamilyName(~str),
            // Generic
//            Serif,
//            SansSerif,
//            Cursive,
//            Fantasy,
//            Monospace,
        }
        pub type SpecifiedValue = ~[FontFamily];
        /// <familiy-name>#
        /// <familiy-name> = <string> | [ <ident>+ ]
        /// TODO: <generic-familiy>
        pub fn parse(input: &[ComponentValue]) -> Option<SpecifiedValue> {
            from_iter(input.skip_whitespace())
        }
        pub fn from_iter<'a>(mut iter: SkipWhitespaceIterator<'a>) -> Option<SpecifiedValue> {
            let mut result = ~[];
            macro_rules! add(
                ($value: expr) => {
                    {
                        result.push($value);
                        match iter.next() {
                            Some(&Comma) => (),
                            None => break 'outer,
                            _ => return None,
                        }
                    }
                }
            )
            'outer: loop {
                match iter.next() {
                    // TODO: avoid copying strings?
                    Some(&String(ref value)) => add!(FamilyName(value.to_owned())),
                    Some(&Ident(ref value)) => {
                        let value = value.as_slice();
                        match value.to_ascii_lower().as_slice() {
//                            "serif" => add!(Serif),
//                            "sans-serif" => add!(SansSerif),
//                            "cursive" => add!(Cursive),
//                            "fantasy" => add!(Fantasy),
//                            "monospace" => add!(Monospace),
                            _ => {
                                let mut idents = ~[value];
                                loop {
                                    match iter.next() {
                                        Some(&Ident(ref value)) => idents.push(value.as_slice()),
                                        Some(&Comma) => {
                                            result.push(FamilyName(idents.connect(" ")));
                                            break
                                        },
                                        None => {
                                            result.push(FamilyName(idents.connect(" ")));
                                            break 'outer
                                        },
                                        _ => return None,
                                    }
                                }
                            }
                        }
                    }
                    _ => return None,
                }
            }
            Some(result)
        }
    </%self:longhand>


    ${single_keyword("font-style", "normal italic oblique", inherited=True)}
    ${single_keyword("font-variant", "normal", inherited=True)}  // Add small-caps when supported

    <%self:single_component_value name="font-weight" inherited="True">
        pub enum SpecifiedValue {
            Bolder,
            Lighther,
            Weight100,
            Weight200,
            Weight300,
            Weight400,
            Weight500,
            Weight600,
            Weight700,
            Weight800,
            Weight900,
        }
        /// normal | bold | bolder | lighter | 100 | 200 | 300 | 400 | 500 | 600 | 700 | 800 | 900
        pub fn from_component_value(input: &ComponentValue) -> Option<SpecifiedValue> {
            match input {
                &Ident(ref value) => match value.to_ascii_lower().as_slice() {
                    "bold" => Some(Weight700),
                    "normal" => Some(Weight400),
                    "bolder" => Some(Bolder),
                    "lighter" => Some(Lighther),
                    _ => None,
                },
                &Number(ref value) => match value.int_value {
                    Some(100) => Some(Weight100),
                    Some(200) => Some(Weight200),
                    Some(300) => Some(Weight300),
                    Some(400) => Some(Weight400),
                    Some(500) => Some(Weight500),
                    Some(600) => Some(Weight600),
                    Some(700) => Some(Weight700),
                    Some(800) => Some(Weight800),
                    Some(900) => Some(Weight900),
                    _ => None,
                },
                _ => None
            }
        }
    </%self:single_component_value>

    <%self:single_component_value name="font-size" inherited="True">
        pub type SpecifiedValue = specified::Length;  // Percentages are the same as em.
        /// <length> | <percentage>
        /// TODO: support <absolute-size> and <relative-size>
        pub fn from_component_value(input: &ComponentValue) -> Option<SpecifiedValue> {
            do specified::LengthOrPercentage::parse_non_negative(input).map_move |value| {
                match value {
                    specified::Length(value) => value,
                    specified::Percentage(value) => specified::Em(value),
                }
            }
        }
    </%self:single_component_value>

    // CSS 2.1, Section 16 - Text

    ${single_keyword("text-align", "left right center justify", inherited=True)}

    <%self:longhand name="text-decoration">
        pub struct SpecifiedValue {
            underline: bool,
            overline: bool,
            line_through: bool,
            // 'blink' is accepted in the parser but ignored.
            // Just not blinking the text is a conforming implementation per CSS 2.1.
        }
        /// none | [ underline || overline || line-through || blink ]
        pub fn parse(input: &[ComponentValue]) -> Option<SpecifiedValue> {
            let mut result = SpecifiedValue {
                underline: false, overline: false, line_through: false,
            };
            let mut blink = false;
            let mut empty = true;
            for component_value in input.skip_whitespace() {
                match get_ident_lower(component_value) {
                    None => return None,
                    Some(keyword) => match keyword.as_slice() {
                        "underline" => if result.underline { return None }
                                      else { empty = false; result.underline = true },
                        "overline" => if result.overline { return None }
                                      else { empty = false; result.overline = true },
                        "line-through" => if result.line_through { return None }
                                          else { empty = false; result.line_through = true },
                        "blink" => if blink { return None }
                                   else { empty = false; blink = true },
                        "none" => return if empty { Some(result) } else { None },
                        _ => return None,
                    }
                }
            }
            if !empty { Some(result) } else { None }
        }
    </%self:longhand>

    // CSS 2.1, Section 17 - Tables

    // CSS 2.1, Section 18 - User interface
}


pub mod shorthands {
    pub use super::*;
    pub use super::longhands::*;

    <%def name="shorthand(name, sub_properties)">
    <%
        shorthand = Shorthand(name, sub_properties.split())
        SHORTHANDS.append(shorthand)
    %>
        pub mod ${shorthand.ident} {
            use super::*;
            struct Longhands {
                % for sub_property in shorthand.sub_properties:
                    ${sub_property.ident}: Option<${sub_property.ident}::SpecifiedValue>,
                % endfor
            }
            pub fn parse(input: &[ComponentValue]) -> Option<Longhands> {
                ${caller.body()}
            }
        }
    </%def>

    <%def name="four_sides_shorthand(name, sub_property_pattern, parser_function)">
        <%self:shorthand name="${name}" sub_properties="${
                ' '.join(sub_property_pattern % side
                         for side in ['top', 'right', 'bottom', 'left'])}">
            let mut iter = input.skip_whitespace().map(${parser_function});
            // zero or more than four values is invalid.
            // one value sets them all
            // two values set (top, bottom) and (left, right)
            // three values set top, (left, right) and bottom
            // four values set them in order
            let top = iter.next().unwrap_or_default(None);
            let right = iter.next().unwrap_or_default(top);
            let bottom = iter.next().unwrap_or_default(top);
            let left = iter.next().unwrap_or_default(right);
            if top.is_some() && right.is_some() && bottom.is_some() && left.is_some()
            && iter.next().is_none() {
                Some(Longhands {
                    % for side in ["top", "right", "bottom", "left"]:
                        ${to_rust_ident(sub_property_pattern % side)}: ${side},
                    % endfor
                })
            } else {
                None
            }
        </%self:shorthand>
    </%def>


    // TODO: other background-* properties
    <%self:shorthand name="background" sub_properties="background-color">
        do one_component_value(input).chain(CSSColor::parse).map_move |color| {
            Longhands { background_color: Some(color) }
        }
    </%self:shorthand>

    ${four_sides_shorthand("border-color", "border-%s-color", "CSSColor::parse")}
    ${four_sides_shorthand("border-style", "border-%s-style", "BorderStyle::parse")}
    ${four_sides_shorthand("border-width", "border-%s-width", "parse_border_width")}

    pub fn parse_border(input: &[ComponentValue]) -> Option<(Option<CSSColor>, Option<BorderStyle>,
                                                             Option<specified::Length>)> {
        let mut color = None;
        let mut style = None;
        let mut width = None;
        let mut any = false;
        for component_value in input.skip_whitespace() {
            if color.is_none() {
                match CSSColor::parse(component_value) {
                    Some(c) => { color = Some(c); any = true; loop },
                    None => ()
                }
            }
            if style.is_none() {
                match BorderStyle::parse(component_value) {
                    Some(s) => { style = Some(s); any = true; loop },
                    None => ()
                }
            }
            if width.is_none() {
                match parse_border_width(component_value) {
                    Some(w) => { width = Some(w); any = true; loop },
                    None => ()
                }
            }
            return None
        }
        if any { Some((color, style, width)) } else { None }
    }

    <%def name="border_side(side)">
        <%self:shorthand name="border-${side}" sub_properties="border-${side}-color
                                                               border-${side}-style
                                                               border-${side}-width">
            do parse_border(input).map_move |(color, style, width)| {
                Longhands { border_${side}_color: color, border_${side}_style: style,
                            border_${side}_width: width }
            }
         </%self:shorthand>
    </%def>

    ${border_side("top")}
    ${border_side("right")}
    ${border_side("bottom")}
    ${border_side("left")}

    <%self:shorthand name="border" sub_properties="
        border-top-color
        border-top-width
        border-top-style
        border-right-color
        border-right-width
        border-right-style
        border-bottom-color
        border-bottom-width
        border-bottom-style
        border-left-color
        border-left-width
        border-left-style
    ">
        do parse_border(input).map_move |(color, style, width)| {
            Longhands {
                border_top_color: color, border_top_style: style, border_top_width: width,
                border_right_color: color, border_right_style: style, border_right_width: width,
                border_bottom_color: color, border_bottom_style: style, border_bottom_width: width,
                border_left_color: color, border_left_style: style, border_left_width: width,
            }
        }
    </%self:shorthand>

}


pub struct PropertyDeclarationBlock {
    important: ~[PropertyDeclaration],
    normal: ~[PropertyDeclaration],
}


pub fn parse_property_declaration_list(input: ~[Node]) -> PropertyDeclarationBlock {
    let mut important = ~[];
    let mut normal = ~[];
    for item in ErrorLoggerIterator(parse_declaration_list(input.move_iter())) {
        match item {
            Decl_AtRule(rule) => log_css_error(
                rule.location, fmt!("Unsupported at-rule in declaration list: @%s", rule.name)),
            Declaration(Declaration{ location: l, name: n, value: v, important: i}) => {
                let list = if i { &mut important } else { &mut normal };
                if !PropertyDeclaration::parse(n, v, list) {
                    log_css_error(l, "Invalid property declaration")
                }
            }
        }
    }
    PropertyDeclarationBlock { important: important, normal: normal }
}


pub enum CSSWideKeyword {
    Initial,
    Inherit,
    Unset,
}

impl CSSWideKeyword {
    pub fn parse(input: &[ComponentValue]) -> Option<CSSWideKeyword> {
        do one_component_value(input).chain(get_ident_lower).chain |keyword| {
            match keyword.as_slice() {
                "initial" => Some(Initial),
                "inherit" => Some(Inherit),
                "unset" => Some(Unset),
                _ => None
            }
        }
    }
}

pub enum DeclaredValue<T> {
    SpecifiedValue(T),
    CSSWideKeyword(CSSWideKeyword),
}

pub enum PropertyDeclaration {
    % for property in LONGHANDS:
        ${property.ident}_declaration(DeclaredValue<longhands::${property.ident}::SpecifiedValue>),
    % endfor
}

impl PropertyDeclaration {
    pub fn parse(name: &str, value: &[ComponentValue],
                 result_list: &mut ~[PropertyDeclaration]) -> bool {
        match name.to_ascii_lower().as_slice() {
            % for property in LONGHANDS:
                "${property.name}" => result_list.push(${property.ident}_declaration(
                    match CSSWideKeyword::parse(value) {
                        Some(keyword) => CSSWideKeyword(keyword),
                        None => match longhands::${property.ident}::parse(value) {
                            Some(value) => SpecifiedValue(value),
                            None => return false,
                        }
                    }
                )),
            % endfor
            % for shorthand in SHORTHANDS:
                "${shorthand.name}" => match CSSWideKeyword::parse(value) {
                    Some(keyword) => {
                        % for sub_property in shorthand.sub_properties:
                            result_list.push(${sub_property.ident}_declaration(
                                CSSWideKeyword(keyword)
                            ));
                        % endfor
                    },
                    None => match shorthands::${shorthand.ident}::parse(value) {
                        Some(result) => {
                            % for sub_property in shorthand.sub_properties:
                                result_list.push(${sub_property.ident}_declaration(
                                    match result.${sub_property.ident} {
                                        Some(value) => SpecifiedValue(value),
                                        None => CSSWideKeyword(Initial),
                                    }
                                ));
                            % endfor
                        },
                        None => return false,
                    }
                },
            % endfor
            _ => return false,  // Unknown property
        }
        true
    }
}
