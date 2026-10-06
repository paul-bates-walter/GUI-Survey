
use iced::mouse;
// iced 0.13 canvas uses the canvas-local `Event` and returns
// (event::Status, Option<Message>) from `update`.
use iced::widget::canvas::event::{Event, Status};
use iced::widget::canvas::{self, Frame, Geometry, Path, Stroke};
use iced::{Color, Point, Rectangle, Renderer, Size, Theme};

use crate::{DrawOp, Message, Mode};

pub struct Editor {
    pub mode: Mode,
    pub pen_color: Color,
    pub pen_radius: f32,
}

#[derive(Default)]
pub enum Pending {
    #[default]
    Idle,
    Anchored(Point),
    Drawing(Point),
}

fn distance(a: Point, b: Point) -> f32 {
    let dx = b.x - a.x;
    let dy = b.y - a.y;
    (dx * dx + dy * dy).sqrt()
}

impl canvas::Program<Message> for Editor {
    type State = Pending;

    fn update(
        &self,
        state: &mut Pending,
        event: Event,
        bounds: Rectangle,
        cursor: mouse::Cursor,
    ) -> (Status, Option<Message>) {
        match event {
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                let Some(pos) = cursor.position_in(bounds) else {
                    return (Status::Ignored, None);
                };
                if let Mode::Path = self.mode {
                    *state = Pending::Drawing(pos);
                    return (Status::Captured, None);
                }
                match *state {
                    // Second click of a two-click shape: commit it.
                    Pending::Anchored(anchor) => {
                        let op = match self.mode {
                            Mode::Circle => DrawOp::Circle {
                                cx: anchor.x,
                                cy: anchor.y,
                                radius: distance(anchor, pos),
                            },
                            Mode::Rectangle => DrawOp::Rect {
                                ax: anchor.x,
                                ay: anchor.y,
                                bx: pos.x,
                                by: pos.y,
                            },
                            Mode::Path => return (Status::Ignored, None),
                        };
                        *state = Pending::Idle;
                        (Status::Captured, Some(Message::Commit(op)))
                    }
                    // First click: drop the anchor.
                    _ => {
                        *state = Pending::Anchored(pos);
                        (Status::Captured, None)
                    }
                }
            }
            Event::Mouse(mouse::Event::CursorMoved { .. }) => {
                let Some(pos) = cursor.position_in(bounds) else {
                    return (Status::Ignored, None);
                };
                match *state {
                    Pending::Drawing(prev) => {
                        *state = Pending::Drawing(pos);
                        (
                            Status::Captured,
                            Some(Message::Commit(DrawOp::Segment {
                                x0: prev.x,
                                y0: prev.y,
                                x1: pos.x,
                                y1: pos.y,
                            })),
                        )
                    }
                    // Capturing triggers a redraw so the rubber-band preview
                    // follows the cursor.
                    Pending::Anchored(_) => (Status::Captured, None),
                    Pending::Idle => (Status::Ignored, None),
                }
            }
            Event::Mouse(mouse::Event::ButtonReleased(mouse::Button::Left)) => {
                if let Pending::Drawing(_) = *state {
                    *state = Pending::Idle;
                }
                (Status::Ignored, None)
            }
            _ => (Status::Ignored, None),
        }
    }

    fn draw(
        &self,
        state: &Pending,
        renderer: &Renderer,
        _theme: &Theme,
        bounds: Rectangle,
        cursor: mouse::Cursor,
    ) -> Vec<Geometry> {
        let mut frame = Frame::new(renderer, bounds.size());

        if let (Pending::Anchored(anchor), Some(pos)) = (state, cursor.position_in(bounds)) {
            let stroke = Stroke::default()
                .with_color(self.pen_color)
                .with_width(self.pen_radius.max(1.0));
            match self.mode {
                Mode::Circle => {
                    let path = Path::circle(*anchor, distance(*anchor, pos));
                    frame.stroke(&path, stroke);
                }
                Mode::Rectangle => {
                    let top_left = Point::new(anchor.x.min(pos.x), anchor.y.min(pos.y));
                    let size = Size::new((pos.x - anchor.x).abs(), (pos.y - anchor.y).abs());
                    frame.stroke(&Path::rectangle(top_left, size), stroke);
                }
                Mode::Path => {}
            }
        }

        vec![frame.into_geometry()]
    }

    fn mouse_interaction(
        &self,
        _state: &Pending,
        bounds: Rectangle,
        cursor: mouse::Cursor,
    ) -> mouse::Interaction {
        if cursor.is_over(bounds) {
            mouse::Interaction::Crosshair
        } else {
            mouse::Interaction::default()
        }
    }
}
