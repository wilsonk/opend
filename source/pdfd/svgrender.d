module pdfd.svgrender;

import std.string;
import pdfd.renderer;

class SVGException : Exception
{
    public
    {
        @safe pure nothrow this(string message,
                                string file =__FILE__,
                                size_t line = __LINE__,
                                Throwable next = null)
        {
            super(message, file, line, next);
        }
    }
}

/// Renders 2D commands in a SVG file.
/// For comparisons between PDF and SVG.
class SVGDocument : IRenderingContext2D
{
public:
    this(int pageWidthMm = 210, int pageHeightMm = 297)
    {
        _pageWidthMm = pageWidthMm;
        _pageHeightMm = pageHeightMm;
        beginPage();

    }

    const(ubyte)[] bytes()
    {
        if (!_finished)
            end();
        auto header = cast(const(ubyte)[])( getHeader() );
        return header ~ _bytes;
    }

    override int pageWidth()
    {
        return _pageWidthMm;
    }

    override int pageHeight()
    {
        return _pageHeightMm;
    }

    override void save()
    {
        _numberOfNestedGroups += 1;
        output("<g>");
    }

    /// Restore the graphical contect: transformation matrices.
    override void restore()
    {        
        foreach(i; 0.._numberOfNestedGroups)
        {
            output("</g>");
        }
        _numberOfNestedGroups = 0;
    }

    /// Start a new page, finish the previous one.
    override void newPage()
    {
        endPage();
        _numberOfPage += 1;
        beginPage();        
    }

    override void fillStyle(string color)
    {
        _currentFill = color;
    }

    override void strokeStyle(string color)
    {
        _currentStroke = color;
    }

    override void fillRect(float x, float y, float width, float height)
    {
        output(format(`<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>`, x, y, width, height, _currentFill));
    }

    override void strokeRect(float x, float y, float width, float height)
    {
        output(format(`<rect x="%s" y="%s" width="%s" height="%s" stroke="%s"/>`, x, y, width, height, _currentStroke));
    }

    override void fillText(string text, float x, float y)
    {
        output(format(`<text x="%f" y="%f" font-family="%s" font-size="%s" fill="%s">%s</text>`, 
                      x, y, _fontFace, _fontSize, _currentFill, text)); 
        // TODO escape XML sequences in text
    }

    override void beginPath(float x, float y)
    {
        _currentPath = format("M%s %s", x, y);
    }

    override void lineWidth(float width)
    {
        _currentLineWidth = width;
    }

    override void lineTo(float dx, float dy)
    {
        _currentPath ~= format(" L%s %s", dx, dy);
    }

    override void fill()
    {
        output(format(`<path d="%s" fill="%s"/>`, _currentPath, _currentFill));
    }

    override void stroke()
    {
        output(format(`<path d="%s" stroke="%s" stroke-width="%s"/>`, _currentPath, _currentStroke, _currentLineWidth));
    }

    override void fillAndStroke()
    {
        output(format(`<path d="%s" fill="%s" stroke="%s" stroke-width="%s"/>`, _currentPath, _currentFill, _currentStroke, _currentLineWidth));
    }

    override void closePath()
    {
        _currentPath ~= " Z";
    }

    override void fontFace(string fontFace)
    {
        _fontFace = fontFace;
    }

    override void fontWeight(FontWeight fontWeight)
    {
        _fontWeight = fontWeight;
    }

    override void fontStyle(FontStyle fontStyle)
    {
        _fontStyle = fontStyle;
    }

    override void fontSize(float size)
    {
        _fontSize = size;
    }

protected:
    string getXMLHeader()
    {
        return `<?xml version="1.0" encoding="UTF-8" standalone="no"?>`;
    }

private:

    bool _finished = false;
    ubyte[] _bytes;

    string _currentFill = "transparent";
    string _currentStroke = "#000";
    float _currentLineWidth = 1;
    int _numberOfNestedGroups = 0;
    int _numberOfPage = 1;
    int _pageWidthMm;
    int _pageHeightMm;

    string _currentPath;

    string _fontFace = "Arial";    
    FontWeight _fontWeight = FontWeight.normal;
    FontStyle _fontStyle = FontStyle.normal;
    float _fontSize = 16;

    void output(ubyte b)
    {
        _bytes ~= b;
    }

    void outputBytes(const(ubyte)[] b)
    {
        _bytes ~= b;
    }

    void output(string s)
    {
        _bytes ~= s.representation;
    }

    void endPage()
    {
        restore();
    }

    void beginPage()
    {        
        output(format(`<g transform="translate(0,%d)">`, _pageHeightMm * (_numberOfPage-1)));
        _numberOfNestedGroups = 1;
    }

    void end()
    {
        if (_finished)
            throw new SVGException("SVGDocument already finalized.");

        _finished = true;

        endPage();
        output(`</svg>`);
    }    

    string getHeader()
    {
        int heightInMm = _pageHeightMm * _numberOfPage;
        return getXMLHeader()
            ~ format(`<svg xmlns="http://www.w3.org/2000/svg" xmlns:svg="http://www.w3.org/2000/svg"`
                     ~` width="%dmm" height="%dmm" viewBox="0 0 %d %d" version="1.1">`,
                     _pageWidthMm, heightInMm, _pageWidthMm, heightInMm);
    }
}