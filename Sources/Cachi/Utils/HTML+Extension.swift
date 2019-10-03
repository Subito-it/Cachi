import Vaux

extension HTML {
    func inlineBlock() -> HTML {
        return style([StyleAttribute(key: "display", value: "inline-block")])
    }
  
    func floatRight() -> HTML {
        style([StyleAttribute(key: "float", value: "right")])
    }

    func iconStyleAttributes(width: Int) -> HTML {
        return style([StyleAttribute(key: "width", value: "\(width)px"),
                      StyleAttribute(key: "height", value: "auto")])
    }
}
